#!/usr/bin/env python3
"""Convert a GIF into coloured ASCII frames for the screensaver.

    gif2ascii.py GIF COLS ROWS ASPECT OUT.json [COLORS] [name=value ...]

Options (set per scene in ScreensaverScenes.js):
    crop=WxH+X+Y   use only this part of the GIF (in GIF pixels)
    key=auto|#rrggbb
                   remove a flat background: pixels close to this colour
                   (auto = the most common colour) become empty, and the rest
                   is drawn as solid blocks coloured from a palette of the
                   foreground only. For light backgrounds, where the normal
                   brightness shading would fill the screen.
    keytol=N       how close counts as background (RGB distance, default 40)
                   key also takes several colours (key=#3b3b3b,#454545, e.g. a
                   checkerboard) or "alpha" (transparent pixels are background)
    size=F         fit into this fraction of the screen (default 1)
    pixel=1        pixel art: scale without smoothing
    still=1        a still image: animate it with a slow bob and a light
                   sweep (48 frames)

COLS x ROWS is the screen's character grid, ASPECT the cell height/width
ratio. The picture is fitted inside the grid (letterboxed) and centred.

Output JSON:
    { cols, rows, x, y, w, h, palette: ["#rrggbb", ...], delays: [ms, ...],
      frames: [ { "c": chars (w*h), "k": colour index per cell (w*h) }, ... ] }
A space in "c" is transparent (the screensaver background shows through).

Only ImageMagick is needed: it does the decoding and resizing, this script
maps pixels to characters and colours.
"""

import json
import math
import os
import subprocess
import sys

RAMPS = {
    "classic": " .:-=+*#%@",
    "blocks": " ░▒▓█",
    "fine": " .'`^\",:;Il!i><~+_-?][}{1)(|/tfjrxnuvczXYUJCLQ0OZmwqpdbkhao*#MW&8%B@$",
}
RAMP = RAMPS[os.environ.get("RAMP", "blocks")]


def run(cmd, binary=False):
    return subprocess.run(cmd, capture_output=True, check=True, text=not binary).stdout


def main(gif, cols, rows, asp, out, *extra):
    ncolors, opt = 7, {}
    for e in extra:
        if "=" in e:
            k, v = e.split("=", 1)
            opt[k] = v
        else:
            ncolors = int(e)
    cols, rows, asp = int(cols), int(rows), float(asp)
    if cols < 20 or rows < 10:
        sys.exit("gif2ascii: grid %dx%d is too small (window not sized yet?)" % (cols, rows))
    crop = opt.get("crop")
    key = opt.get("key")
    keytol = float(opt.get("keytol", 40))
    size = float(opt.get("size", 1))
    still = opt.get("still") == "1"

    info = run(["magick", "identify", "-format", "%T %w %h\n", gif]).split("\n")
    info = [l.split() for l in info if l.strip()]
    delays = [max(20, int(l[0]) * 10) for l in info]          # centiseconds -> ms
    gw, gh = int(info[0][1]), int(info[0][2])
    pre = []
    if crop:
        pre = ["-crop", crop, "+repage"]
        cw_, ch_ = crop.split("+")[0].split("x")
        gw, gh = int(cw_), int(ch_)

    # fit the picture inside the grid; a cell is `asp` times taller than wide
    aspect = gw / gh
    fr, fc = max(1, int(rows * size)), max(1, int(cols * size))
    h = fr
    w = round(h * asp * aspect)
    if w > fc:
        w = fc
        h = max(1, round(w / (asp * aspect)))
    x, y = (cols - w) // 2, (rows - h) // 2

    filt = ["-filter", "point"] if opt.get("pixel") == "1" else []
    keys = (key or "").split(",")
    if "alpha" in keys:
        # keep transparency: it is the background (plus any colours listed)
        rgba = run(["magick", gif, "-coalesce"] + pre + filt + ["-resize", "%dx%d!" % (w, h), "-depth", "8", "rgba:-"], binary=True)
        n = len(rgba) // (w * h * 4)
        px = [(rgba[p], rgba[p + 1], rgba[p + 2]) for p in range(0, len(rgba) - 3, 4)]
        cols_ = [tuple(int(k.strip().lstrip("#")[i:i + 2], 16) for i in (0, 2, 4)) for k in keys if k != "alpha"]
        tol2 = keytol * keytol
        bgm = [rgba[p + 3] < 128 or any((rgba[p] - b[0]) ** 2 + (rgba[p + 1] - b[1]) ** 2 + (rgba[p + 2] - b[2]) ** 2 < tol2
                                        for b in cols_)
               for p in range(0, len(rgba) - 3, 4)]
        return keyed(px, bgm, n, w, h, x, y, cols, rows, asp, delays, out, ncolors, still)
    raw = run(["magick", gif, "-coalesce"] + pre + ["-background", "black", "-alpha", "remove", "-alpha", "off"]
              + filt + ["-resize", "%dx%d!" % (w, h), "-depth", "8", "rgb:-"], binary=True)
    n = len(raw) // (w * h * 3)
    delays = (delays + [delays[-1]] * n)[:n]

    # a small palette shared by all frames (the colour layers)
    pal_txt = run(["magick", gif, "-coalesce"] + pre + ["-resize", "48x48!", "-append",
                   "+dither", "-colors", str(ncolors), "-unique-colors", "txt:-"])
    palette = []
    for line in pal_txt.splitlines():
        i = line.find("#")
        if i >= 0 and not line.startswith("#"):
            hx = line[i:i + 7]
            palette.append(tuple(int(hx[k:k + 2], 16) for k in (1, 3, 5)))
    palette = palette[:9] or [(255, 255, 255)]

    if key:
        px = [(raw[p], raw[p + 1], raw[p + 2]) for p in range(0, len(raw) - 2, 3)]
        if key == "auto":
            counts = {}
            for c in px[:w * h]:
                q = (c[0] >> 3, c[1] >> 3, c[2] >> 3)
                counts[q] = counts.get(q, 0) + 1
            q = max(counts, key=counts.get)
            bgs = [(q[0] * 8 + 4, q[1] * 8 + 4, q[2] * 8 + 4)]
        else:
            bgs = [tuple(int(k.strip().lstrip("#")[i:i + 2], 16) for i in (0, 2, 4)) for k in key.split(",")]
        tol2 = keytol * keytol
        bgm = [any((c[0] - b[0]) ** 2 + (c[1] - b[1]) ** 2 + (c[2] - b[2]) ** 2 < tol2 for b in bgs) for c in px]
        return keyed(px, bgm, n, w, h, x, y, cols, rows, asp, delays, out, ncolors, still)

    # brightness range across the whole clip, for contrast stretching
    lum = [0] * 256
    step = max(1, len(raw) // 3 // 200000)
    for p in range(0, len(raw) - 2, 3 * step):
        lum[(raw[p] * 299 + raw[p + 1] * 587 + raw[p + 2] * 114) // 1000] += 1
    total = sum(lum)
    acc, lo, hi = 0, 0, 255
    for v in range(256):
        acc += lum[v]
        if acc < total * 0.02:
            lo = v
        if acc < total * 0.985:
            hi = v
    span = max(1, hi - lo)

    cache = {}

    def nearest(r, g, b):
        key = (r >> 3, g >> 3, b >> 3)
        if key not in cache:
            best, bd = 0, 1 << 30
            for i, (pr, pg, pb) in enumerate(palette):
                d = (r - pr) ** 2 * 3 + (g - pg) ** 2 * 4 + (b - pb) ** 2 * 2
                if d < bd:
                    best, bd = i, d
            cache[key] = str(best)
        return cache[key]

    frames = []
    size = w * h * 3
    last = len(RAMP) - 1
    for f in range(n):
        base = f * size
        chars, kinds = [], []
        for p in range(base, base + size, 3):
            r, g, b = raw[p], raw[p + 1], raw[p + 2]
            l = ((r * 299 + g * 587 + b * 114) // 1000 - lo) / span
            if l < 0.07:
                chars.append(" ")
                kinds.append("0")
                continue
            l = min(1.0, l) ** 0.85
            chars.append(RAMP[max(1, int(l * last))])
            kinds.append(nearest(r, g, b))
        frames.append({"c": "".join(chars), "k": "".join(kinds)})

    # thin glyphs on black need light colours: lift each palette colour so its
    # brightest channel is high, keeping its hue
    def lift(rgb):
        m = max(rgb) or 1
        f = min(4.0, max(1.0, 225 / m))
        return tuple(min(255, int(c * f + 18)) for c in rgb)
    hexpal = ["#%02x%02x%02x" % lift(rgb) for rgb in palette]
    data = {"cols": cols, "rows": rows, "asp": asp, "x": x, "y": y, "w": w, "h": h,
            "palette": hexpal, "delays": delays, "frames": frames}
    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    with open(out + ".tmp", "w") as fh:
        json.dump(data, fh, separators=(",", ":"))
    os.replace(out + ".tmp", out)


def animate_still(px, bgm, w, h, frames=48):
    """A still image -> frames: bobs one row up and down and a band of light
    sweeps across it diagonally once per loop."""
    opx, obg, delays = [], [], []
    for f in range(frames):
        ph = f / frames
        dy = round(math.sin(ph * 2 * math.pi))           # -1, 0, 1 rows
        band = ph * 1.8 - 0.4
        for yy in range(h):
            sy = yy - dy
            for xx in range(w):
                if not 0 <= sy < h:
                    opx.append((0, 0, 0)); obg.append(True); continue
                i = sy * w + xx
                c = px[i]
                if not bgm[i]:
                    d = abs((xx / w + sy / h) / 2 - band)
                    if d < 0.07:
                        k = 0.55 * (1 - d / 0.07)
                        c = tuple(int(v + (255 - v) * k) for v in c)
                opx.append(c); obg.append(bgm[i])
        delays.append(80)
    return opx, obg, frames, delays


def keyed(px, bgm, n, w, h, x, y, cols, rows, asp, delays, out, ncolors, still):
    """Flat-background mode: background -> empty, foreground -> solid blocks.
    px: (r, g, b) per pixel for all frames, bgm: True where it's background."""
    if still:
        px, bgm, n, delays = animate_still(px[:w * h], bgm[:w * h], w, h)

    # palette: k-means over a sample of foreground pixels
    fg = [c for c, b in zip(px[::7], bgm[::7]) if not b] or [(255, 255, 255)]
    step = max(1, len(fg) // 4000)
    sample = fg[::step]
    # seed with colours far apart (so small but distinct areas, like a red
    # stripe, get their own colour), then refine with k-means
    cent = [sample[len(sample) // 2]]
    while len(cent) < ncolors:
        cent.append(max(sample, key=lambda c: min((c[0] - r) ** 2 + (c[1] - g) ** 2 + (c[2] - b) ** 2
                                                   for r, g, b in cent)))

    def near(c, cs):
        best, bd = 0, 1 << 30
        for i, (r, g, b) in enumerate(cs):
            d = (c[0] - r) ** 2 * 3 + (c[1] - g) ** 2 * 4 + (c[2] - b) ** 2 * 2
            if d < bd:
                best, bd = i, d
        return best

    for _ in range(8):
        sums = [[0, 0, 0, 0] for _ in cent]
        for c in sample:
            i = near(c, cent)
            s = sums[i]
            s[0] += c[0]; s[1] += c[1]; s[2] += c[2]; s[3] += 1
        cent = [(s[0] // s[3], s[1] // s[3], s[2] // s[3]) if s[3] else cent[i] for i, s in enumerate(sums)]

    cache = {}
    frames = []
    for f in range(n):
        chars, kinds = [], []
        base = f * w * h
        for i in range(w * h):
            c = px[base + i]
            if bgm[base + i]:
                chars.append(" ")
                kinds.append("0")
                continue
            q = (c[0] >> 3, c[1] >> 3, c[2] >> 3)
            if q not in cache:
                cache[q] = str(near(c, cent))
            chars.append("█")
            kinds.append(cache[q])
        frames.append({"c": "".join(chars), "k": "".join(kinds)})

    # very dark colours vanish on black: lift them a little, keep the hue
    def lift(rgb):
        m = max(rgb) or 1
        f = max(1.0, 110 / m)
        return tuple(min(255, int(c * f)) for c in rgb)
    data = {"cols": cols, "rows": rows, "asp": asp, "x": x, "y": y, "w": w, "h": h,
            "palette": ["#%02x%02x%02x" % lift(c) for c in cent], "delays": delays, "frames": frames}
    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    with open(out + ".tmp", "w") as fh:
        json.dump(data, fh, separators=(",", ":"))
    os.replace(out + ".tmp", out)


if __name__ == "__main__":
    if len(sys.argv) < 6:
        print(__doc__.strip())
        sys.exit(2)
    main(*sys.argv[1:])
