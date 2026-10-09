#!/usr/bin/env python3
"""Mouse and keyboard settings for Settings > Mouse / Keyboard (Hyprland).

    inputctl.py state                  everything the pages show, as JSON
    inputctl.py set KEY VALUE ...      change options (live + saved)
    inputctl.py remap FROM TO DESC     move a bind (FROM = its combo in the config)
    inputctl.py disable FROM DESC      switch a bind off
    inputctl.py reset FROM | reset-all put binds back

Options are saved in ~/.config/hypr/settings.json and rendered to settings.lua,
which hyprland.lua loads last, so they win over its defaults; they are also
applied at once with `hyprctl eval hl.config(...)`. Moved binds are saved in
keybinds.json and rendered to keybinds.lua, which hyprland.lua's hl.bind wrapper
reads; those need a config reload, done here.
"""

import json
import os
import re
import subprocess
import sys
from pathlib import Path

HYPR = Path.home() / ".config/hypr"
SETTINGS_JSON = HYPR / "settings.json"
SETTINGS_LUA = HYPR / "settings.lua"
BINDS_JSON = HYPR / "keybinds.json"
BINDS_LUA = HYPR / "keybinds.lua"

# option -> (kind, check); kind matches getoption's JSON field
OPTIONS = {
    "input:sensitivity": ("float", lambda v: -1 <= v <= 1),
    "input:accel_profile": ("str", lambda v: v in ("flat", "adaptive", "")),
    "input:natural_scroll": ("bool", None),
    "input:scroll_factor": ("float", lambda v: 0.05 <= v <= 10),
    "input:left_handed": ("bool", None),
    "input:follow_mouse": ("int", lambda v: v in (0, 1, 2, 3)),
    "input:repeat_rate": ("int", lambda v: 1 <= v <= 200),
    "input:repeat_delay": ("int", lambda v: 100 <= v <= 3000),
    "input:kb_layout": ("str", lambda v: re.fullmatch(r"[a-z]{2,3}(,[a-z]{2,3})*", v)),
    "input:kb_variant": ("str", lambda v: re.fullmatch(r"[a-z0-9_-]*(,[a-z0-9_-]*)*", v)),
    "input:kb_options": ("str", lambda v: re.fullmatch(r"[a-z0-9_:,-]*", v)),
    "input:numlock_by_default": ("bool", None),
    "input:touchpad:natural_scroll": ("bool", None),
    "input:touchpad:tap_to_click": ("bool", None),
    "input:touchpad:disable_while_typing": ("bool", None),
    "input:touchpad:scroll_factor": ("float", lambda v: 0.05 <= v <= 10),
    "cursor:hide_on_key_press": ("bool", None),
    "cursor:inactive_timeout": ("float", lambda v: 0 <= v <= 3600),
}

MOD_BITS = [(64, "SUPER"), (4, "CTRL"), (8, "ALT"), (1, "SHIFT")]
ORDER = {"SUPER": 0, "CTRL": 1, "ALT": 2, "SHIFT": 3}
ALIASES = {"MOD4": "SUPER", "WIN": "SUPER", "LOGO": "SUPER", "META": "SUPER", "CONTROL": "CTRL", "MOD1": "ALT"}
KEY = re.compile(r"^[A-Za-z0-9_:]{1,40}$")


def hyprctl(*args):
    return subprocess.run(["hyprctl", *args], capture_output=True, text=True).stdout


def load(path, default):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return default


def write(path, text):
    tmp = path.with_name("." + path.name + ".tmp")
    tmp.write_text(text)
    os.replace(tmp, path)


# ------------------------------------------------------------------ options

def live_options():
    out = {}
    text = hyprctl("--batch", "-j", "; ".join("getoption " + k for k in OPTIONS))
    decoder, i = json.JSONDecoder(), 0
    while True:
        while i < len(text) and text[i] not in "{":
            i += 1
        if i >= len(text):
            break
        try:
            obj, i = decoder.raw_decode(text, i)
        except ValueError:
            break
        name = obj.get("option")
        if name in OPTIONS:
            value = obj.get(OPTIONS[name][0])
            out[name] = "" if value == "[[EMPTY]]" else value
    return out


def lua_value(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    return '"' + str(v).replace("\\", "\\\\").replace('"', '\\"') + '"'


def lua_table(flat):
    """{"input:touchpad:tap_to_click": True} -> 'input = { touchpad = { tap_to_click = true } }'"""
    tree = {}
    for key, value in flat.items():
        node, parts = tree, key.split(":")
        for part in parts[:-1]:
            node = node.setdefault(part, {})
        node[parts[-1]] = value

    def render(node):
        return "{ " + ", ".join(f"{k} = {render(v) if isinstance(v, dict) else lua_value(v)}"
                                for k, v in node.items()) + " }"
    return render(tree)


def coerce(key, raw):
    kind, check = OPTIONS[key]
    if kind == "bool":
        value = raw in (True, "true", "1", 1)
    elif kind == "int":
        value = int(raw)
    elif kind == "float":
        value = round(float(raw), 3)
    else:
        value = str(raw).strip()
    if check and not check(value):
        raise SystemExit(f"inputctl: {key} can't be {raw!r}")
    return value


def set_options(pairs):
    saved = load(SETTINGS_JSON, {})
    changed = {}
    for key, raw in pairs:
        if key not in OPTIONS:
            raise SystemExit(f"inputctl: unknown option {key}")
        changed[key] = saved[key] = coerce(key, raw)
    write(SETTINGS_JSON, json.dumps(saved, indent=2) + "\n")
    write(SETTINGS_LUA, "-- Generated by Settings > Mouse / Keyboard "
          "(~/.config/quickshell/input/inputctl.py); do not edit.\n"
          f"hl.config({lua_table(saved)})\n")
    hyprctl("eval", f"hl.config({lua_table(changed)})")


# ------------------------------------------------------------------- binds

def norm(combo):
    """Canonical "SUPER + SHIFT + D"; compare with .lower() on the key like the Lua side."""
    mods, key = [], ""
    for part in str(combo).split("+"):
        part = part.strip()
        up = ALIASES.get(part.upper(), part.upper())
        if up in ORDER:
            mods.append(up)
        elif part:
            key = part
    mods = sorted(set(mods), key=ORDER.get)
    return " + ".join(mods + [key])


def match_key(combo):
    c = norm(combo)
    head, _, key = c.rpartition(" + ")
    return (head + " + " if head else "") + key.lower()


def from_hyprctl(b):
    mods = [name for bit, name in MOD_BITS if b.get("modmask", 0) & bit]
    return norm(" + ".join(mods + [b.get("key") or f"code:{b.get('keycode')}"]))


def render_binds(moves):
    lines = ["-- Generated by Settings > Keyboard (~/.config/quickshell/input/inputctl.py); do not edit.",
             "return {"]
    for orig, m in sorted(moves.items()):
        to = "false" if m.get("to") is None else lua_value(m["to"])
        lines.append(f"    [{lua_value(orig)}] = {to},  -- {m.get('description', '')}")
    lines.append("}")
    write(BINDS_LUA, "\n".join(lines) + "\n")
    write(BINDS_JSON, json.dumps(moves, indent=2) + "\n")
    hyprctl("reload")


def binds_state():
    moves = load(BINDS_JSON, {})
    by_target = {match_key(m["to"]): orig for orig, m in moves.items() if m.get("to")}
    live = json.loads(hyprctl("binds", "-j") or "[]")
    out = []
    for b in live:
        if b.get("submap"):
            continue
        combo = from_hyprctl(b)
        orig = by_target.get(match_key(combo), combo)
        out.append({"combo": combo, "orig": orig, "moved": orig != combo,
                    "description": b.get("description") or "", "mouse": bool(b.get("mouse")),
                    "locked": bool(b.get("locked"))})
    for orig, m in moves.items():
        if m.get("to") is None:
            out.append({"combo": "", "orig": orig, "moved": True, "disabled": True,
                        "description": m.get("description", ""), "mouse": False, "locked": False})
    return out


def main():
    args = sys.argv[1:]
    cmd = args[0] if args else "state"
    if cmd == "state":
        cursor = subprocess.run([str(Path.home() / ".config/theme/cursor/cursor-accent"), "status"],
                                capture_output=True, text=True).stdout
        devices = json.loads(hyprctl("devices", "-j") or "{}")
        print(json.dumps({
            "options": live_options(),
            "saved": load(SETTINGS_JSON, {}),
            "touchpad": any("touchpad" in m.get("name", "") for m in devices.get("mice", [])),
            "mice": [m.get("name") for m in devices.get("mice", [])],
            "keyboards": [k.get("name") for k in devices.get("keyboards", []) if "button" not in k.get("name", "")],
            "cursor": json.loads(cursor) if cursor.strip() else None,
            "binds": binds_state(),
        }))
    elif cmd == "set":
        pairs = args[1:]
        if not pairs or len(pairs) % 2:
            raise SystemExit("inputctl.py set KEY VALUE [KEY VALUE ...]")
        set_options(list(zip(pairs[::2], pairs[1::2])))
    elif cmd in ("remap", "disable", "reset", "reset-all"):
        moves = load(BINDS_JSON, {})
        if cmd == "reset-all":
            moves = {}
        else:
            orig = norm(args[1])
            if cmd == "reset":
                moves.pop(orig, None)
            else:
                to = norm(args[2]) if cmd == "remap" else None
                desc = args[3] if cmd == "remap" else (args[2] if len(args) > 2 else "")
                if to is not None:
                    if not KEY.match(to.rpartition(" + ")[2]):
                        raise SystemExit(f"inputctl: odd key in {to}")
                    if match_key(to) == match_key(orig):
                        moves.pop(orig, None)
                        render_binds(moves)
                        return
                moves[orig] = {"to": to, "description": desc}
        render_binds(moves)
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
