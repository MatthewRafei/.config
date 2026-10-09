#!/usr/bin/env python3
"""Claude Code sessions for the bar's agents chip (Agents.qml).

  agents.py scan          JSON list of running sessions on stdout
  agents.py recent        JSON list of recent sessions that aren't running (to resume)
  agents.py focus PID     focus the terminal window that PID runs in (Hyprland or niri)
  agents.py attached NAME focus a terminal attached to kept session NAME (exit 1: none)

A session is "kept" when it runs inside the private tmux server (`tmux -L claude`,
config agents/tmux.conf): closing its terminal only detaches it, and the bar can open
it again. Other sessions live and die with their terminal.

Live state comes from Claude Code's session registry (~/.claude/sessions/<pid>.json:
status busy / idle / waiting), titles from the transcript's latest "ai-title" record.
Both are internal formats, so everything here degrades to "unknown" rather than failing.
Standard library only.
"""
import json
import os
import re
import subprocess
import sys

CLAUDE = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
TMUX = ["tmux", "-L", "claude"]
TITLE_TAIL = 512 * 1024          # bytes of a transcript searched for its title


def run(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=5, check=False).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


def ppid(pid):
    try:
        with open(f"/proc/{pid}/stat") as f:
            return int(f.read().rsplit(")", 1)[1].split()[1])
    except (OSError, ValueError, IndexError):
        return 0


def ancestors(pid):
    out = []
    while pid > 1 and len(out) < 64:
        out.append(pid)
        pid = ppid(pid)
    return out


def proc_start(pid):
    """Field 22 of /proc/PID/stat (start time in clock ticks), to spot reused pids."""
    try:
        with open(f"/proc/{pid}/stat") as f:
            return f.read().rsplit(")", 1)[1].split()[19]
    except (OSError, IndexError):
        return None


def title(cwd, sid):
    """The newest ai-title / custom title in the session's transcript."""
    proj = re.sub(r"[^A-Za-z0-9]", "-", cwd)
    path = os.path.join(CLAUDE, "projects", proj, f"{sid}.jsonl")
    try:
        with open(path, "rb") as f:
            f.seek(0, 2)
            size = f.tell()
            f.seek(max(0, size - TITLE_TAIL))
            tail = f.read().decode("utf-8", "replace")
    except OSError:
        return ""
    found = ""
    for m in re.finditer(r'"(?:customTitle|aiTitle)"\s*:\s*"((?:[^"\\]|\\.)*)"', tail):
        found = m.group(1)
    try:
        return json.loads(f'"{found}"') if found else ""
    except ValueError:
        return found


def tmux_panes():
    """pane pid -> {session, attached, created}"""
    panes = {}
    fmt = "#{pane_pid}\t#{session_name}\t#{session_attached}\t#{session_created}\t#{pane_current_path}"
    for line in run(TMUX + ["list-panes", "-a", "-F", fmt]).splitlines():
        f = line.split("\t")
        if len(f) == 5 and f[0].isdigit():
            panes[int(f[0])] = {"session": f[1], "attached": int(f[2] or 0), "created": int(f[3] or 0), "cwd": f[4]}
    return panes


def scan():
    panes = tmux_panes()
    out = []
    reg = os.path.join(CLAUDE, "sessions")
    try:
        names = os.listdir(reg)
    except OSError:
        names = []
    seen_tmux = set()
    for name in names:
        if not name.endswith(".json"):
            continue
        try:
            with open(os.path.join(reg, name)) as f:
                s = json.load(f)
            pid = int(s["pid"])
        except (OSError, ValueError, KeyError, TypeError):
            continue
        if not os.path.exists(f"/proc/{pid}"):
            continue
        if s.get("procStart") and proc_start(pid) not in (None, str(s["procStart"])):
            continue                                    # the pid was reused
        if s.get("kind") not in (None, "interactive"):
            continue                                    # skip `claude -p` runs and the like
        chain = ancestors(pid)
        pane = next((panes[p] for p in chain if p in panes), None)
        if pane:
            seen_tmux.add(pane["session"])
        cwd = s.get("cwd") or ""
        out.append({
            "pid": pid,
            "sid": s.get("sessionId", ""),
            "cwd": cwd,
            "title": title(cwd, s.get("sessionId", "")) or s.get("name") or os.path.basename(cwd) or "claude",
            "status": s.get("status") or "unknown",
            "since": s.get("statusUpdatedAt") or s.get("updatedAt") or 0,
            "started": s.get("startedAt") or 0,
            "tmux": pane["session"] if pane else "",
            "attached": pane["attached"] if pane else 1,
        })
    # kept sessions whose claude hasn't registered yet: Claude Code only writes its
    # registry entry once past the start screen (e.g. the "trust this folder?" prompt)
    for p in panes.values():
        if p["session"] not in seen_tmux:
            seen_tmux.add(p["session"])
            out.append({"pid": 0, "sid": "", "cwd": p["cwd"], "title": "New session", "status": "new",
                        "since": p["created"] * 1000, "started": p["created"] * 1000,
                        "tmux": p["session"], "attached": p["attached"]})
    out.sort(key=lambda x: x["started"])
    print(json.dumps(out))


def recent(limit=8):
    """Newest transcripts whose session isn't running: [{sid, cwd, title, mtime}]"""
    running = set()
    reg = os.path.join(CLAUDE, "sessions")
    try:
        for name in os.listdir(reg):
            if name.endswith(".json"):
                try:
                    with open(os.path.join(reg, name)) as f:
                        s = json.load(f)
                    if os.path.exists(f"/proc/{int(s['pid'])}"):
                        running.add(s.get("sessionId"))
                except (OSError, ValueError, KeyError, TypeError):
                    pass
    except OSError:
        pass
    files = []
    root = os.path.join(CLAUDE, "projects")
    try:
        for d in os.listdir(root):
            full = os.path.join(root, d)
            if not os.path.isdir(full):
                continue
            for f in os.listdir(full):
                if f.endswith(".jsonl") and f[:-6] not in running:
                    p = os.path.join(full, f)
                    try:
                        files.append((os.path.getmtime(p), p))
                    except OSError:
                        pass
    except OSError:
        pass
    out = []
    for mtime, p in sorted(files, reverse=True):
        sid = os.path.basename(p)[:-6]
        cwd = ""
        try:
            with open(p, "rb") as f:          # the first records carry the cwd
                for _ in range(40):
                    line = f.readline()
                    if not line:
                        break
                    m = re.search(rb'"cwd"\s*:\s*"((?:[^"\\]|\\.)*)"', line)
                    if m:
                        cwd = json.loads(b'"' + m.group(1) + b'"')
                        break
        except (OSError, ValueError):
            continue
        t = title(cwd, sid) if cwd else ""
        if not cwd or not t or not os.path.isdir(cwd):
            continue                          # no conversation worth resuming
        out.append({"sid": sid, "cwd": cwd, "title": t, "mtime": int(mtime * 1000)})
        if len(out) >= limit:
            break
    print(json.dumps(out))


def attached(name):
    for line in run(TMUX + ["list-clients", "-t", name, "-F", "#{client_pid}"]).splitlines():
        if line.strip().isdigit() and focus(int(line)) == 0:
            return 0
    return 1


def focus(pid):
    """Focus the window of the nearest ancestor that owns one."""
    chain = ancestors(pid)
    if os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        try:
            clients = json.loads(run(["hyprctl", "-j", "clients"]) or "[]")
        except ValueError:
            return 1
        by_pid = {c.get("pid"): c.get("address") for c in clients}
        for p in chain:
            addr = by_pid.get(p)
            if addr and re.fullmatch(r"0x[0-9a-f]+", addr):
                run(["hyprctl", "dispatch", f'hl.dsp.focus({{ window = "address:{addr}" }})'])
                return 0
    elif os.environ.get("NIRI_SOCKET"):
        try:
            wins = json.loads(run(["niri", "msg", "--json", "windows"]) or "[]")
        except ValueError:
            return 1
        by_pid = {w.get("pid"): w.get("id") for w in wins}
        for p in chain:
            wid = by_pid.get(p)
            if isinstance(wid, int):
                run(["niri", "msg", "action", "focus-window", "--id", str(wid)])
                return 0
    return 1


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == "scan":
        scan()
        return 0
    if len(sys.argv) >= 2 and sys.argv[1] == "recent":
        recent()
        return 0
    if len(sys.argv) == 3 and sys.argv[1] == "focus" and sys.argv[2].isdigit():
        return focus(int(sys.argv[2]))
    if len(sys.argv) == 3 and sys.argv[1] == "attached" and re.fullmatch(r"[A-Za-z0-9_.-]+", sys.argv[2]):
        return attached(sys.argv[2])
    print(__doc__, file=sys.stderr)
    return 64


if __name__ == "__main__":
    sys.exit(main())
