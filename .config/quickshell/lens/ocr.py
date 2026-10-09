#!/usr/bin/env python3
"""Lens OCR: crop a screenshot region and read it with tesseract (Lens.qml).

usage: ocr.py <png> <x> <y> <w> <h> <scale> <langs>

stdout: one `W<TAB>par<TAB>line<TAB>x<TAB>y<TAB>w<TAB>h<TAB>word` per word (logical px,
relative to the crop, in reading order), then `CONF<TAB><0-100>`. Failures print
`ERR<TAB><reason>`: badregion, badimage, nolang, notess, fail.

Adapted from scribe's engine (github.com/lunanoir21/scribe, MIT), on Pillow alone (no numpy):
  1. Fast pass: grayscale, polarity guessed from the mean brightness, the crop cut into
     strips at blank rows, the strips read by parallel tesseract processes.
  2. If that pass explains most of the "ink" (edges) in the crop, done. Plain text ends here.
  3. Otherwise (gradients, busy backgrounds, mixed light/dark text) read it again with both
     polarities, two scales and two page modes; the best pass wins and confident words from
     the others fill the gaps.
  4. Words are put into reading order (columns kept apart), numbered into lines and paragraphs.
"""
import math
import os
import re
import shutil
import statistics
import subprocess
import sys
import tempfile
from collections import namedtuple
from concurrent.futures import ThreadPoolExecutor

from PIL import Image, ImageChops, ImageDraw, ImageOps, ImageStat

sys.dont_write_bytecode = True
Image.MAX_IMAGE_PIXELS = 120_000_000

Word = namedtuple("Word", "text conf x y w h")   # crop pixels

MIN_WORD_CONF = 40
SUPPLEMENT_CONF = 70        # words added from a losing pass must be this sure
UPSCALE_BELOW = 150_000     # px area: small selections are read at 2x
COVERAGE_OK = 0.85          # share of ink the fast pass must explain to skip the extra passes
INK_EDGE = 70               # gradient strength that counts as ink
CELL = 32                   # px grid for pockets of unexplained ink
CELL_INK = 0.10
CELL_LIMIT = 4
MIN_STRIP = 70
EXTRA_STRIP = 140
MAX_STRIPS = 12
MAX_CROP_PIXELS = 36_000_000
MAX_WORDS = 4000
MAX_WORD_CHARS = 120
STRIP_TIMEOUT = 60


def allowed_image(path):
    """Only the screenshot Lens itself took ($XDG_RUNTIME_DIR/lens)."""
    base = os.environ.get("XDG_RUNTIME_DIR", "")
    return bool(base) and os.path.dirname(os.path.realpath(path)) == os.path.realpath(os.path.join(base, "lens"))


def parse_region(args):
    try:
        x, y, w, h, scale = (float(v) for v in args)
    except ValueError:
        return None
    if not all(math.isfinite(v) for v in (x, y, w, h, scale)):
        return None
    if w < 1 or h < 1 or scale < 0.25 or scale > 8:
        return None
    return x, y, w, h, scale


# ── image helpers ───────────────────────────────────────────────────────────
def row_ranges(gray):
    """Per-row brightness range (max - min)."""
    w, data = gray.width, gray.tobytes()
    return [max(data[i:i + w]) - min(data[i:i + w]) for i in range(0, len(data), w)]


def split_rows(gray, n):
    """Row indices to cut `gray` into n strips, preferring blank rows."""
    h = gray.height
    if n <= 1:
        return [0, h]
    ptp = row_ranges(gray)
    cuts, span = [0], h / n
    for k in range(1, n):
        target = int(span * k)
        lo = max(cuts[-1] + MIN_STRIP, target - int(span * 0.4))
        hi = min(h - MIN_STRIP, target + int(span * 0.4))
        if lo >= hi:
            continue
        blank = [r for r in range(lo, hi) if ptp[r] < 28]
        cuts.append(min(blank, key=lambda r: abs(r - target)) if blank
                    else min(range(lo, hi), key=lambda r: ptp[r]))
    cuts.append(h)
    return cuts


# ── reading ─────────────────────────────────────────────────────────────────
def clean_word(text):
    return "".join(ch for ch in text if ch.isprintable()).strip()[:MAX_WORD_CHARS]


def read_strip(job):
    idx, img, y_off, up, psm, langs, tmp, tess = job
    path = os.path.join(tmp, f"s{idx}.png")
    img.save(path)
    try:
        out = subprocess.run(
            [tess, path, "stdout", "-l", langs, "--oem", "1", "--psm", str(psm),
             "-c", "tessedit_do_invert=0", "tsv"],
            capture_output=True, text=True, env=dict(os.environ, OMP_THREAD_LIMIT="1"),
            timeout=STRIP_TIMEOUT, check=False,
        ).stdout
    except subprocess.TimeoutExpired:
        return []
    words = []
    for row in out.split("\n")[1:]:
        c = row.split("\t")
        if len(c) < 12 or c[0] != "5":
            continue
        text = clean_word(c[11])
        try:
            conf = float(c[10])
            left, top, width, height = int(c[6]), int(c[7]), int(c[8]), int(c[9])
        except ValueError:
            continue
        if text and conf >= MIN_WORD_CONF:
            words.append(Word(text, conf, left / up, (top + y_off) / up, width / up, height / up))
    return words


def pass_jobs(gray, up, psm, strips, langs, tmp, tess, tag):
    cuts = split_rows(gray, strips)
    img = gray
    if up != 1.0:
        img = gray.resize((max(8, int(gray.width * up)), max(8, int(gray.height * up))), Image.LANCZOS)
    jobs = []
    for i in range(len(cuts) - 1):
        y0, y1 = int(cuts[i] * up), int(cuts[i + 1] * up)
        jobs.append((f"{tag}{i}", img.crop((0, y0, img.width, y1)), y0, up, psm, langs, tmp, tess))
    return jobs


def run_jobs(jobs, pool):
    words = []
    for part in pool.map(read_strip, jobs):
        words += part
    return words


# ── quality ─────────────────────────────────────────────────────────────────
def alpha_ratio(text):
    return sum(ch.isalnum() for ch in text) / max(1, len(text))


def plausible(w):
    """Drop stray marks and unsure one-letter 'words'."""
    if w.w < 3 or w.h < 5:
        return False
    if len(w.text) == 1 and w.conf < 85:
        return False
    return alpha_ratio(w.text) >= 0.5 or w.conf >= 85


def quality(words):
    return sum((w.conf / 100) ** 2 * min(len(w.text), 8) * alpha_ratio(w.text)
               for w in words if plausible(w))


def ink_mask(lum):
    """Edge pixels (|dx| + |dy| > INK_EDGE) as a 0/255 image."""
    dx = ImageChops.difference(lum, ImageChops.offset(lum, -1, 0))
    dy = ImageChops.difference(lum, ImageChops.offset(lum, 0, -1))
    ink = ImageChops.add(dx, dy).point(lambda v: 255 if v > INK_EDGE else 0)
    # offset() wraps around: drop the last column and row
    return ink.crop((0, 0, max(1, lum.width - 1), max(1, lum.height - 1)))


def uncovered_ink(ink, words):
    """-> (coverage, cells): share of ink inside word boxes, and CELL squares of dense ink left over."""
    total = ink.histogram()[255]
    if total < 60:
        return 1.0, 0
    left = ink.copy()
    d = ImageDraw.Draw(left)
    for w in words:
        d.rectangle([int(w.x) - 2, int(w.y) - 2, int(w.x + w.w) + 2, int(w.y + w.h) + 2], fill=0)
    rest = left.histogram()[255]
    cells = 0
    gw, gh = left.width // CELL, left.height // CELL
    if gw and gh:
        grid = left.crop((0, 0, gw * CELL, gh * CELL)).resize((gw, gh), Image.BOX)
        cells = sum(grid.histogram()[int(255 * CELL_INK) + 1:])
    return (total - rest) / total, cells


def overlaps(a, b):
    ix = min(a.x + a.w, b.x + b.w) - max(a.x, b.x)
    iy = min(a.y + a.h, b.y + b.h) - max(a.y, b.y)
    if ix <= 0 or iy <= 0:
        return False
    small = min(a.w * a.h, b.w * b.h)
    return small > 0 and ix * iy / small > 0.3


def merge_passes(passes):
    ranked = sorted(passes.values(), key=quality, reverse=True)
    chosen = [w for w in ranked[0] if plausible(w)]
    for words in ranked[1:]:
        for w in words:
            if w.conf < SUPPLEMENT_CONF or not plausible(w) or alpha_ratio(w.text) < 0.8:
                continue
            if not any(overlaps(w, c) for c in chosen):
                chosen.append(w)
    return chosen


# ── reading order ───────────────────────────────────────────────────────────
def build_lines(words):
    """Words in the same horizontal band, split at wide gaps."""
    if not words:
        return []
    med_h = statistics.median(w.h for w in words)
    bands, cur, cur_cy = [], [], None
    for w in sorted(words, key=lambda w: w.y + w.h / 2):
        cy = w.y + w.h / 2
        if cur and abs(cy - cur_cy) > 0.6 * max(min(w.h, statistics.median(x.h for x in cur)), 4):
            bands.append(cur)
            cur = []
        cur.append(w)
        cur_cy = statistics.mean(x.y + x.h / 2 for x in cur)
    bands.append(cur)
    lines = []
    for band in bands:
        band.sort(key=lambda w: w.x)
        seg = [band[0]]
        for w in band[1:]:
            if w.x - (seg[-1].x + seg[-1].w) > max(2.5 * max(w.h, seg[-1].h), 28, 2.0 * med_h):
                lines.append(seg)
                seg = []
            seg.append(w)
        lines.append(seg)
    return lines


def box(line):
    return (min(w.x for w in line), min(w.y for w in line),
            max(w.x + w.w for w in line), max(w.y + w.h for w in line))


def xy_cut(lines, med_h, gid=0):
    """Order lines by recursively splitting at the widest empty row band (top first) or
    column band (left first). -> [(line, group id)]"""
    if len(lines) <= 1:
        return [(ln, gid) for ln in lines]
    boxes = [box(ln) for ln in lines]

    def best_gap(lo_i, hi_i):
        spans = sorted((b[lo_i], b[hi_i]) for b in boxes)
        best, edge, reach = 0, None, spans[0][1]
        for lo, hi in spans[1:]:
            if lo - reach > best:
                best, edge = lo - reach, (reach + lo) / 2
            reach = max(reach, hi)
        return best, edge

    gy, cut_y = best_gap(1, 3)
    gx, cut_x = best_gap(0, 2)
    if gy >= 0.5 * med_h and gy >= gx / 2:
        a = [ln for ln, b in zip(lines, boxes) if (b[1] + b[3]) / 2 < cut_y]
        b_ = [ln for ln, b in zip(lines, boxes) if (b[1] + b[3]) / 2 >= cut_y]
        if a and b_:
            return xy_cut(a, med_h, gid) + xy_cut(b_, med_h, gid + 1000)
    if gx >= 2.0 * med_h:
        a = [ln for ln, b in zip(lines, boxes) if (b[0] + b[2]) / 2 < cut_x]
        b_ = [ln for ln, b in zip(lines, boxes) if (b[0] + b[2]) / 2 >= cut_x]
        if a and b_:
            return xy_cut(a, med_h, gid) + xy_cut(b_, med_h, gid + 1)
    return [(ln, gid) for ln in sorted(lines, key=lambda ln: (box(ln)[1], box(ln)[0]))]


def reading_order(words):
    """-> [(par, line, Word)] in reading order."""
    lines = build_lines(words)
    if not lines:
        return []
    med_h = statistics.median(w.h for w in words)
    out, par, prev = [], 0, None
    for n, (ln, gid) in enumerate(xy_cut(lines, med_h)):
        x0, y0, x1, y1 = box(ln)
        if prev is not None:
            if gid != prev[4] or y0 - prev[3] > 0.9 * max(y1 - y0, prev[3] - prev[1]):
                par += 1
        out += [(par, n, w) for w in ln]
        prev = (x0, y0, x1, y1, gid)
    return out


# ── driver ──────────────────────────────────────────────────────────────────
def extract(rgb, langs, tess, workers, tmp):
    lum = rgb.convert("L")
    w, h = lum.size
    small = w * h < UPSCALE_BELOW
    base_up = 2.0 if small else 1.0
    normal, inverted = ImageOps.autocontrast(lum), ImageOps.autocontrast(ImageOps.invert(lum))
    guess_inverted = ImageStat.Stat(lum).mean[0] < 128

    with ThreadPoolExecutor(max_workers=workers) as pool:
        strips = 1 if small else max(1, min(workers, MAX_STRIPS, h // MIN_STRIP))
        base = run_jobs(pass_jobs(inverted if guess_inverted else normal, base_up, 6, strips,
                                  langs, tmp, tess, "b"), pool)
        cover, cells = uncovered_ink(ink_mask(lum), base)
        if cover >= COVERAGE_OK and cells < CELL_LIMIT:
            return [wd for wd in base if plausible(wd)]

        e_strips = 1 if small else max(1, min(workers, MAX_STRIPS, h // EXTRA_STRIP))
        ups = (2.0, 1.0) if small else (1.0, 0.5)
        all_jobs, owners = [], []
        for pol, gray in (("n", normal), ("i", inverted)):
            for up in ups:
                for psm in (6, 11):
                    if pol == ("i" if guess_inverted else "n") and up == base_up and psm == 6:
                        continue            # the fast pass already did this one
                    name = f"{pol}{up}p{psm}"
                    js = pass_jobs(gray, up, psm, e_strips, langs, tmp, tess, name)
                    all_jobs += js
                    owners += [name] * len(js)
        passes = {"base": base}
        for name, words in zip(owners, pool.map(read_strip, all_jobs)):
            passes.setdefault(name, []).extend(words)
        return merge_passes(passes)


def main():
    if len(sys.argv) != 8:
        print("ERR\tusage")
        return 64
    png, langs = sys.argv[1], sys.argv[7]
    region = parse_region(sys.argv[2:7])
    if region is None or not re.fullmatch(r"[A-Za-z_]+(\+[A-Za-z_]+)*", langs):
        print("ERR\tbadregion")
        return 64
    if not allowed_image(png):
        print("ERR\tbadimage")
        return 64
    tess = shutil.which("tesseract")
    if not tess:
        print("ERR\tnotess")
        return 1
    x, y, w, h, scale = region
    try:
        full = Image.open(png).convert("RGB")
        left, top = max(0, int(x * scale)), max(0, int(y * scale))
        right, bottom = min(full.width, int((x + w) * scale)), min(full.height, int((y + h) * scale))
        if right - left < 2 or bottom - top < 2 or (right - left) * (bottom - top) > MAX_CROP_PIXELS:
            print("ERR\tbadregion")
            return 64
        crop = full.crop((left, top, right, bottom))
        del full
        with tempfile.TemporaryDirectory(prefix="lens-") as tmp:
            words = extract(crop, langs, tess, min(os.cpu_count() or 4, MAX_STRIPS), tmp)
    except (OSError, ValueError, MemoryError):
        print("ERR\tfail")
        return 1

    ordered = reading_order(words[:MAX_WORDS])
    conf = sum(wd.conf for *_, wd in ordered) / len(ordered) if ordered else 0
    for par, line, wd in ordered:
        print(f"W\t{par}\t{line}\t{wd.x / scale:.1f}\t{wd.y / scale:.1f}\t{wd.w / scale:.1f}\t"
              f"{wd.h / scale:.1f}\t{wd.text}")
    print(f"CONF\t{int(conf)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
