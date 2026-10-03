// nightlightd: flicker-free night light for wlroots-style compositors (niri).
//
// gammastep -O applies one temperature and must be killed and restarted to
// change it; in between the compositor restores normal gamma, so the screen
// flashes white. This keeps the gamma control open and fades between
// temperatures instead.
//
// Reads one colour temperature (Kelvin) per line on stdin, e.g. "3500".
// 6500 means neutral (no tint). Each change fades over FADE_MS. Exits (and the
// compositor restores normal gamma) when stdin closes.
//
// Build: see Makefile.

#define _GNU_SOURCE
#include <errno.h>
#include <math.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>

#include "wlr-gamma-control-unstable-v1-client-protocol.h"

#define NEUTRAL_K 6500.0
#define FADE_MS 250.0
#define FRAME_MS 16

struct output {
    struct wl_output *wl;
    struct zwlr_gamma_control_v1 *gamma;
    uint32_t size;
    int failed;
    struct output *next;
};

static struct zwlr_gamma_control_manager_v1 *manager;
static struct output *outputs;
static struct wl_display *display;

static double current_k = NEUTRAL_K, from_k = NEUTRAL_K, target_k = NEUTRAL_K;
static double fade_start_ms = -1;

static double now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
}

// Tanner Helland's blackbody approximation, normalised so 6500K is neutral.
static void blackbody(double k, double rgb[3]) {
    double t = k / 100.0, r, g, b;
    if (t <= 66) {
        r = 255;
        g = 99.4708025861 * log(t) - 161.1195681661;
        b = t <= 19 ? 0 : 138.5177312231 * log(t - 10) - 305.0447927307;
    } else {
        r = 329.698727446 * pow(t - 60, -0.1332047592);
        g = 288.1221695283 * pow(t - 60, -0.0755148492);
        b = 255;
    }
    rgb[0] = r / 255; rgb[1] = g / 255; rgb[2] = b / 255;
    for (int i = 0; i < 3; i++)
        rgb[i] = rgb[i] < 0 ? 0 : rgb[i] > 1 ? 1 : rgb[i];
}

static void whitepoint(double k, double rgb[3]) {
    double ref[3];
    blackbody(k, rgb);
    blackbody(NEUTRAL_K, ref);
    for (int i = 0; i < 3; i++) {
        rgb[i] /= ref[i];
        if (rgb[i] > 1) rgb[i] = 1;
    }
}

static void apply_output(struct output *o, double k) {
    if (!o->gamma || o->failed || o->size == 0)
        return;
    size_t bytes = (size_t)o->size * 3 * sizeof(uint16_t);
    int fd = memfd_create("nightlightd-ramp", MFD_CLOEXEC);
    if (fd < 0 || ftruncate(fd, bytes) < 0) {
        if (fd >= 0) close(fd);
        return;
    }
    uint16_t *ramp = mmap(NULL, bytes, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (ramp == MAP_FAILED) {
        close(fd);
        return;
    }
    double wp[3];
    whitepoint(k, wp);
    for (uint32_t i = 0; i < o->size; i++) {
        double v = (double)i / (o->size - 1);
        for (int c = 0; c < 3; c++)
            ramp[c * o->size + i] = (uint16_t)(v * wp[c] * 65535.0 + 0.5);
    }
    munmap(ramp, bytes);
    zwlr_gamma_control_v1_set_gamma(o->gamma, fd);
    close(fd);
}

static void apply_all(double k) {
    for (struct output *o = outputs; o; o = o->next)
        apply_output(o, k);
    wl_display_flush(display);
}

// ---- gamma control events ----
static void gamma_size(void *data, struct zwlr_gamma_control_v1 *g, uint32_t size) {
    (void)g;
    struct output *o = data;
    o->size = size;
    apply_output(o, current_k);
}

static void gamma_failed(void *data, struct zwlr_gamma_control_v1 *g) {
    struct output *o = data;
    o->failed = 1;
    zwlr_gamma_control_v1_destroy(g);
    o->gamma = NULL;
    fprintf(stderr, "nightlightd: gamma control refused (another tool like gammastep running?)\n");
}

static const struct zwlr_gamma_control_v1_listener gamma_listener = {
    .gamma_size = gamma_size,
    .failed = gamma_failed,
};

static void setup_output(struct output *o) {
    if (!manager || o->gamma)
        return;
    o->gamma = zwlr_gamma_control_manager_v1_get_gamma_control(manager, o->wl);
    zwlr_gamma_control_v1_add_listener(o->gamma, &gamma_listener, o);
}

// ---- registry ----
static void reg_global(void *data, struct wl_registry *reg, uint32_t name,
                       const char *iface, uint32_t version) {
    (void)data; (void)version;
    if (strcmp(iface, wl_output_interface.name) == 0) {
        struct output *o = calloc(1, sizeof *o);
        o->wl = wl_registry_bind(reg, name, &wl_output_interface, 1);
        o->next = outputs;
        outputs = o;
        setup_output(o);   // no-op until the manager is bound
    } else if (strcmp(iface, zwlr_gamma_control_manager_v1_interface.name) == 0) {
        manager = wl_registry_bind(reg, name, &zwlr_gamma_control_manager_v1_interface, 1);
        for (struct output *o = outputs; o; o = o->next)
            setup_output(o);
    }
}

static void reg_remove(void *data, struct wl_registry *reg, uint32_t name) {
    (void)data; (void)reg; (void)name;   // outputs going away clean up server-side
}

static const struct wl_registry_listener reg_listener = {
    .global = reg_global,
    .global_remove = reg_remove,
};

// ---- stdin ----
static int read_stdin(void) {
    static char buf[256];
    static size_t len;
    ssize_t n = read(STDIN_FILENO, buf + len, sizeof buf - 1 - len);
    if (n <= 0)
        return 0;   // closed
    len += n;
    buf[len] = 0;
    char *line, *nl;
    for (line = buf; (nl = strchr(line, '\n')); line = nl + 1) {
        *nl = 0;
        double k = atof(line);
        if (k >= 1000 && k <= 25000 && fabs(k - target_k) > 0.5) {
            from_k = current_k;
            target_k = k;
            fade_start_ms = now_ms();
        }
    }
    len = strlen(line);
    memmove(buf, line, len + 1);
    if (len == sizeof buf - 1) len = 0;   // overlong garbage line
    return 1;
}

int main(void) {
    display = wl_display_connect(NULL);
    if (!display) {
        fprintf(stderr, "nightlightd: cannot connect to Wayland display\n");
        return 1;
    }
    struct wl_registry *reg = wl_display_get_registry(display);
    wl_registry_add_listener(reg, &reg_listener, NULL);
    wl_display_roundtrip(display);
    if (!manager) {
        fprintf(stderr, "nightlightd: compositor lacks wlr-gamma-control\n");
        return 1;
    }
    wl_display_roundtrip(display);

    struct pollfd fds[2] = {
        { .fd = wl_display_get_fd(display), .events = POLLIN },
        { .fd = STDIN_FILENO, .events = POLLIN },
    };

    for (;;) {
        wl_display_flush(display);
        int timeout = fade_start_ms >= 0 ? FRAME_MS : -1;
        if (poll(fds, 2, timeout) < 0) {
            if (errno == EINTR) continue;
            break;
        }
        if (fds[0].revents & POLLIN) {
            if (wl_display_dispatch(display) < 0) break;
        }
        if (fds[0].revents & (POLLERR | POLLHUP)) break;
        if (fds[1].revents & (POLLIN | POLLHUP)) {
            if (!read_stdin()) break;
        }
        if (fade_start_ms >= 0) {
            double p = (now_ms() - fade_start_ms) / FADE_MS;
            if (p >= 1) { p = 1; fade_start_ms = -1; }
            p = p * p * (3 - 2 * p);   // smoothstep
            current_k = from_k + (target_k - from_k) * p;
            apply_all(current_k);
        }
    }
    wl_display_disconnect(display);
    return 0;
}
