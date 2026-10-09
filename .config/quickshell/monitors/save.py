#!/usr/bin/env python3
"""Write the monitor layout kept in Settings > Monitors into Hyprland's config.

    save.py CONFIG JSON

JSON is a list of {name, mode, x, y, scale, transform, enabled}. Each
`hl.monitor({ output = "NAME", ... })` line for a listed output is replaced in
place (other fields on it, like vrr or bitdepth, are kept); outputs without a
line get one after the last monitor rule. The previous file is kept as
CONFIG.bak. Everything else in the file is left alone.
"""

import json
import os
import re
import shutil
import sys
import tempfile

RULE = re.compile(r'^(\s*)hl\.monitor\(\s*\{(.*)\}\s*\)\s*(--.*)?$')
FIELD = re.compile(r'(\w+)\s*=\s*("(?:\\.|[^"\\])*"|[\w.+-]+)\s*(?:,|$)')
MANAGED = ("output", "mode", "position", "scale", "transform", "disabled")
NAME = re.compile(r'^[A-Za-z0-9_.:-]{1,64}$')
MODE = re.compile(r'^\d{2,5}x\d{2,5}@\d{1,3}(\.\d{1,3})?$')


def fields(body):
    """The rule's fields in order, or None for anything that isn't plain key = value."""
    out, end = [], 0
    for match in FIELD.finditer(body):
        if body[end:match.start()].strip():
            return None
        out.append((match[1], match[2]))
        end = match.end()
    return out if not body[end:].strip() else None


def render(monitor, extras):
    values = [("output", f'"{monitor["name"]}"')]
    if monitor["enabled"]:
        values += [("mode", f'"{monitor["mode"]}"'),
                   ("position", f'"{int(monitor["x"])}x{int(monitor["y"])}"'),
                   ("scale", f'{float(monitor["scale"]):g}')]
        if int(monitor["transform"]):
            values.append(("transform", str(int(monitor["transform"]))))
    else:
        values.append(("disabled", "true"))
    values += [kv for kv in extras if kv[0] not in MANAGED]
    return values


def align(rows):
    """Pad each column so the rules line up, the way the file is written by hand."""
    widths = {}
    for _, values in rows:
        for i, (k, v) in enumerate(values[:-1]):
            widths[i] = max(widths.get(i, 0), len(f"{k} = {v},"))
    lines = []
    for indent, values in rows:
        parts = [f"{k} = {v}," .ljust(widths[i]) if i < len(values) - 1 else f"{k} = {v}"
                 for i, (k, v) in enumerate(values)]
        lines.append(f"{indent}hl.monitor({{ {' '.join(parts)} }})")
    return lines


def main():
    path, monitors = sys.argv[1], json.loads(sys.argv[2])
    for m in monitors:
        if not NAME.match(m["name"]) or (m["enabled"] and not MODE.match(m["mode"])):
            sys.exit(f"refusing odd monitor values: {m!r}")
    if not any(m["enabled"] for m in monitors):
        sys.exit("refusing a layout with every monitor off")
    with open(path) as f:
        lines = f.read().split("\n")

    by_name = {m["name"]: m for m in monitors}
    found, rows, last = {}, {}, -1
    for i, line in enumerate(lines):
        match = RULE.match(line)
        if not match:
            continue
        last = i
        values = fields(match[2])
        if values is None:
            continue
        output = dict(values).get("output", "").strip('"')
        if output in by_name and output not in found:
            found[output] = i
            rows[i] = (match[1], render(by_name[output], values))
    new = [(None, ("", render(m, []))) for m in monitors if m["name"] not in found]

    # line the rewritten rules (and any new ones) up together
    keys = sorted(rows)
    aligned = align([rows[k] for k in keys] + [row for _, row in new])
    for k, text in zip(keys, aligned):
        lines[k] = text
    added = aligned[len(keys):]
    if added:
        at = last + 1 if last >= 0 else len(lines)
        lines[at:at] = added

    shutil.copy2(path, path + ".bak")
    directory = os.path.dirname(os.path.abspath(path))
    fd, tmp = tempfile.mkstemp(prefix=".machine.", dir=directory)
    with os.fdopen(fd, "w") as f:
        f.write("\n".join(lines))
    shutil.copymode(path, tmp)
    os.replace(tmp, path)


if __name__ == "__main__":
    main()
