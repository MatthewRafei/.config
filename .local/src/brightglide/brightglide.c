// brightglide: smooth, natural-feeling backlight changes.
//
// brillo fades each step in 4 linear jumps (one every 20 ms) and a held key
// stops between steps, so changes look like a staircase that pulses. This
// works in perceived lightness (CIE L*, so every step looks the same size)
// and glides there with a critically damped spring at ~120 Hz: it eases in
// and out, and a held key just moves the target, so the motion never stops.
//
//   brightglide up | down    one step (STEP L*) brighter / darker
//   brightglide set N        go to N (0-100, perceived lightness)
//   brightglide get          print the current perceived lightness
//
// The first call animates; calls made while it runs only move its target.
// Needs write access to /sys/class/backlight/*/brightness (the video group).
//
// Build: see Makefile.

#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <time.h>
#include <unistd.h>

#define STEP 5.0          // L* per key press (0-100 scale)
#define MIN_L 8.0         // never go fully black (about 0.9% of max)
#define OMEGA 26.0        // spring stiffness: ~95% of the way in 180 ms
#define FRAME_NS 8333333L // ~120 Hz

static char dev[512];
static long max_raw;

static int find_device(void) {
    DIR *d = opendir("/sys/class/backlight");
    if (!d) return -1;
    struct dirent *e;
    while ((e = readdir(d))) {
        if (e->d_name[0] == '.') continue;
        snprintf(dev, sizeof dev, "/sys/class/backlight/%s", e->d_name);
        char p[600];
        snprintf(p, sizeof p, "%s/max_brightness", dev);
        FILE *f = fopen(p, "r");
        if (!f) continue;
        int ok = fscanf(f, "%ld", &max_raw) == 1 && max_raw > 0;
        fclose(f);
        if (ok) { closedir(d); return 0; }
    }
    closedir(d);
    return -1;
}

static long read_raw(void) {
    char p[600];
    long v = -1;
    snprintf(p, sizeof p, "%s/actual_brightness", dev);
    FILE *f = fopen(p, "r");
    if (f) { if (fscanf(f, "%ld", &v) != 1) v = -1; fclose(f); }
    return v;
}

static int bfd = -1;
static long last_written = -1;
static void write_raw(long v) {
    if (v == last_written) return;
    char buf[32];
    int n = snprintf(buf, sizeof buf, "%ld", v);
    if (pwrite(bfd, buf, n, 0) == n) last_written = v;
}

// perceived lightness <-> linear fraction (CIE 1976 L*)
static double to_l(double y) {
    return y > 0.008856 ? 116.0 * cbrt(y) - 16.0 : 903.3 * y;
}
static double from_l(double l) {
    return l > 8.0 ? pow((l + 16.0) / 116.0, 3) : l / 903.3;
}
static long l_to_raw(double l) {
    long r = lround(from_l(l) * max_raw);
    return r < 1 ? 1 : r > max_raw ? max_raw : r;
}
static double clamp_l(double l) {
    return l < MIN_L ? MIN_L : l > 100.0 ? 100.0 : l;
}

// target, shared between calls through a small file in the runtime dir
static char tpath[512], apath[512];
static double read_target(int fd) {
    char buf[64] = {0};
    ssize_t n = pread(fd, buf, sizeof buf - 1, 0);
    return n > 0 ? atof(buf) : -1;
}
static void write_target(int fd, double t) {
    char buf[64];
    int n = snprintf(buf, sizeof buf, "%.4f\n", t);
    if (ftruncate(fd, 0) == 0 && pwrite(fd, buf, n, 0) != n) perror("brightglide: target");
}

static double now(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: brightglide up | down | set N | get\n");
        return 2;
    }
    if (find_device() < 0) { fprintf(stderr, "brightglide: no backlight\n"); return 1; }

    long raw = read_raw();
    double cur_l = to_l((double)raw / max_raw);
    if (!strcmp(argv[1], "get")) { printf("%.1f\n", cur_l); return 0; }

    const char *rt = getenv("XDG_RUNTIME_DIR");
    if (!rt) rt = "/tmp";
    snprintf(tpath, sizeof tpath, "%s/brightglide.target", rt);
    snprintf(apath, sizeof apath, "%s/brightglide.anim", rt);
    int tfd = open(tpath, O_RDWR | O_CREAT, 0600);
    int afd = open(apath, O_RDWR | O_CREAT, 0600);
    if (tfd < 0 || afd < 0) { perror("brightglide"); return 1; }

    // read-modify-write the target under the target lock. If nobody is
    // animating, start from what the screen shows now (brillo or a power
    // profile may have changed it); otherwise from the running target.
    flock(tfd, LOCK_EX);
    int animating = flock(afd, LOCK_EX | LOCK_NB) != 0;
    double base = animating ? read_target(tfd) : cur_l;
    if (base < 0) base = cur_l;
    double target;
    if (!strcmp(argv[1], "up")) target = base + STEP;
    else if (!strcmp(argv[1], "down")) target = base - STEP;
    else if (!strcmp(argv[1], "set") && argc > 2) target = atof(argv[2]);
    else { flock(tfd, LOCK_UN); fprintf(stderr, "brightglide: bad arguments\n"); return 2; }
    target = clamp_l(target);
    write_target(tfd, target);
    flock(tfd, LOCK_UN);
    if (animating) return 0;   // the running instance picks the new target up

    // we hold the animation lock: glide until we reach the (moving) target
    char p[600];
    snprintf(p, sizeof p, "%s/brightness", dev);
    bfd = open(p, O_WRONLY);
    if (bfd < 0) { perror("brightglide: brightness"); flock(afd, LOCK_UN); return 1; }
    last_written = raw;

    double x = cur_l, v = 0, t_prev = now();
    struct timespec frame = { 0, FRAME_NS };
    for (;;) {
        nanosleep(&frame, NULL);
        double t = now(), dt = t - t_prev;
        t_prev = t;
        if (dt > 0.05) dt = 0.05;

        double goal = read_target(tfd);
        if (goal < 0) goal = target;

        // critically damped spring, exact step: no overshoot, eases in and out
        double d = x - goal, e = exp(-OMEGA * dt);
        double c = v + OMEGA * d;
        x = goal + (d + c * dt) * e;
        v = (v - OMEGA * c * dt) * e;
        write_raw(l_to_raw(x));

        if (fabs(x - goal) < 0.05 && fabs(v) < 0.5) {
            // settle exactly; quit unless a new target arrived meanwhile
            flock(tfd, LOCK_EX);
            double again = read_target(tfd);
            if (again >= 0 && fabs(again - goal) > 1e-6) { flock(tfd, LOCK_UN); continue; }
            write_raw(l_to_raw(goal));
            flock(afd, LOCK_UN);
            flock(tfd, LOCK_UN);
            break;
        }
    }
    return 0;
}
