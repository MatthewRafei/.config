#!/usr/bin/env python3
"""QR codes for Beam.qml (after TouchWorkStation/Omarchy-Beam-), fully local.

    beam.py encode          text on stdin -> JSON { status, kind, label, preview, size, rows }
    beam.py history [N]     the last N text entries of cliphist -> JSON [{ id, preview }]
    beam.py entry ID        cliphist entry ID, encoded like `encode`

status is ok | empty | toolarge. rows are strings of 0/1 modules, quiet zone
not included (the overlay draws its own). Error correction H, so glare and a
phone held at an angle still scan. QR encoding by the vendored segno (BSD).
"""

import json
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "vendor"))
import segno  # noqa: E402

MAX_BYTES = 1200

RE_WIFI = re.compile(r"^WIFI:[A-Za-z]?:?.*;", re.S)
RE_URL = re.compile(r"^https?://\S+$")
RE_WWW = re.compile(r"^www\.[^\s/]+\.[a-z]{2,}\S*$", re.I)
RE_MAILTO = re.compile(r"^mailto:\S+$")
RE_EMAIL = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")
RE_TEL = re.compile(r"^(tel:)?\+?[0-9][-0-9(). ]{5,}$")


def classify(text):
    """(kind, label, payload, preview)"""
    t = text.strip()
    one = "\n" not in t
    if RE_WIFI.match(t):
        ssid = re.search(r"S:([^;]*);", t)
        return "wifi", "SCAN TO JOIN", t, "Wi-Fi: " + (ssid.group(1) if ssid else "network")
    if one and RE_URL.match(t):
        return "url", "SCAN TO OPEN", t, re.sub(r"^https?://", "", t).rstrip("/")
    if one and RE_WWW.match(t):
        return "url", "SCAN TO OPEN", "https://" + t, t
    if one and RE_MAILTO.match(t):
        return "email", "SCAN TO EMAIL", t, t[7:]
    if one and RE_EMAIL.match(t):
        return "email", "SCAN TO EMAIL", "mailto:" + t, t
    if one and RE_TEL.match(t):
        number = t[4:] if t.startswith("tel:") else t
        return "tel", "SCAN TO CALL", "tel:" + re.sub(r"[^\d+]", "", number), number
    return "text", "SCAN TO COPY", text, text


def preview(s, kind):
    s = " ".join(re.sub(r"[\x00-\x1f\x7f]", " ", s).split())
    limit = 180 if kind == "text" else 60
    return s if len(s) <= limit else s[:limit - 1] + "…"


def encode(text):
    if not text.strip():
        return {"status": "empty", "label": "NOTHING TO BEAM", "preview": "Copy a link or some text first."}
    kind, label, payload, shown = classify(text)
    size = len(payload.encode("utf-8"))
    if size > MAX_BYTES:
        return {"status": "toolarge", "kind": kind, "label": "TOO BIG TO BEAM",
                "preview": f"{size} bytes; a QR a phone can read holds about {MAX_BYTES}."}
    qr = segno.make(payload, error="h", micro=False, boost_error=True)
    rows = ["".join("1" if m else "0" for m in row) for row in qr.matrix_iter(border=0)]
    return {"status": "ok", "kind": kind, "label": label, "preview": preview(shown, kind),
            "bytes": size, "version": qr.version, "size": len(rows), "rows": rows}


def history(n):
    out = subprocess.run(["cliphist", "list"], capture_output=True, text=True).stdout
    items = []
    for line in out.splitlines():
        ident, _, text = line.partition("\t")
        if not ident.isdigit() or text.startswith("[[ binary data"):
            continue
        items.append({"id": ident, "preview": preview(text, "text")[:80]})
        if len(items) >= n:
            break
    return items


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "encode"
    if cmd == "encode":
        print(json.dumps(encode(sys.stdin.read())))
    elif cmd == "history":
        print(json.dumps(history(int(sys.argv[2]) if len(sys.argv) > 2 else 30)))
    elif cmd == "entry":
        ident = sys.argv[2] if len(sys.argv) > 2 else ""
        if not ident.isdigit():
            raise SystemExit("beam.py entry ID")
        text = subprocess.run(["cliphist", "decode", ident], capture_output=True).stdout.decode("utf-8", "replace")
        print(json.dumps(encode(text)))
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
