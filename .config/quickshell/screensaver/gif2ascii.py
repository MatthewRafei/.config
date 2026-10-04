#!/usr/bin/env python3
"""Convert a GIF into coloured ASCII frames for the screensaver.

    gif2ascii.py GIF COLS ROWS ASPECT OUT.json [COLORS]

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


def main(gif, cols, rows, asp, out, ncolors=7):
    cols, rows, asp, ncolors = int(cols), int(rows), float(asp), int(ncolors)

    info = run(["magick", "identify", "-format", "%T %w %h\n", gif]).split("\n")
    info = [l.split() for l in info if l.strip()]
    delays = [max(20, int(l[0]) * 10) for l in info]          # centiseconds -> ms
    gw, gh = int(info[0][1]), int(info[0][2])

    # fit the picture inside the grid; a cell is `asp` times taller than wide
    aspect = gw / gh
    h = rows
    w = round(h * asp * aspect)
    if w > cols:
        w = cols
        h = max(1, round(w / (asp * aspect)))
    x, y = (cols - w) // 2, (rows - h) // 2

    raw = run(["magick", gif, "-coalesce", "-resize", "%dx%d!" % (w, h), "-depth", "8", "rgb:-"], binary=True)
    n = len(raw) // (w * h * 3)
    delays = (delays + [delays[-1]] * n)[:n]

    # a small palette shared by all frames (the colour layers)
    pal_txt = run(["magick", gif, "-coalesce", "-resize", "48x48!", "-append",
                   "+dither", "-colors", str(ncolors), "-unique-colors", "txt:-"])
    palette = []
    for line in pal_txt.splitlines():
        i = line.find("#")
        if i >= 0 and not line.startswith("#"):
            hx = line[i:i + 7]
            palette.append(tuple(int(hx[k:k + 2], 16) for k in (1, 3, 5)))
    palette = palette[:9] or [(255, 255, 255)]

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


if __name__ == "__main__":
    if len(sys.argv) < 6:
        print(__doc__.strip())
        sys.exit(2)
    main(*sys.argv[1:7])
