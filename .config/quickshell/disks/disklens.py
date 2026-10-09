#!/usr/bin/env python3
"""What is taking the space: a folder scan for Settings > Disks (after
mtolhuys/omarchy-disk-lens, WinDirStat style).

    disklens.py mounts          capacity of every real mounted filesystem (JSON)
    disklens.py scan PATH       scan PATH; progress lines on stderr, tree JSON on stdout
    disklens.py trash PATH      move one file or folder to the desktop Trash (gio)

The scan stays on PATH's filesystem, counts hardlinked files once, measures
allocated size (what deleting would actually free) and never follows
symlinks. The tree keeps every folder and file big enough to see; the rest of
a folder's contents is summed into one "smaller items" entry, so drilling in
never needs another scan. Unreadable folders are counted, not hidden.
"""

import heapq
import json
import os
import stat
import subprocess
import sys
import time

KEEP = 60            # largest entries kept per folder
MIN_SHARE = 1 / 4000 # ... and only those above this share of the whole scan


def mounts():
    out = []
    seen = set()
    for line in open("/proc/self/mounts"):
        dev, mnt, fstype = line.split()[:3]
        mnt = mnt.encode().decode("unicode_escape")
        if not dev.startswith("/dev/") or fstype in ("squashfs", "iso9660") or dev in seen:
            continue
        seen.add(dev)
        try:
            st = os.statvfs(mnt)
        except OSError:
            continue
        total = st.f_blocks * st.f_frsize
        free = st.f_bavail * st.f_frsize
        if total <= 0:
            continue
        out.append({"mount": mnt, "device": dev, "fstype": fstype, "total": total,
                    "used": total - st.f_bfree * st.f_frsize, "free": free})
    return sorted(out, key=lambda m: (m["mount"] != "/", m["mount"]))


class Scan:
    def __init__(self, root):
        self.root = os.path.realpath(root)
        self.dev = os.lstat(self.root).st_dev
        self.inodes = set()
        self.files = 0
        self.dirs = 0
        self.errors = 0
        self.bytes = 0
        self.last = 0.0

    def progress(self, where):
        now = time.monotonic()
        if now - self.last > 0.25:
            self.last = now
            print(json.dumps({"files": self.files, "dirs": self.dirs, "bytes": self.bytes,
                              "at": where[len(self.root):] or "/"}), file=sys.stderr, flush=True)

    def walk(self, path, name):
        """-> node {n, s, d: true, c: [...], k: item count}; files are [n, s, mtime]."""
        self.dirs += 1
        size, count, subdirs, files = 0, 0, [], []
        try:
            it = os.scandir(path)
        except OSError:
            self.errors += 1
            return {"n": name, "s": 0, "d": True, "c": [], "k": 0, "x": True}
        with it:
            for e in it:
                try:
                    st = e.stat(follow_symlinks=False)
                except OSError:
                    self.errors += 1
                    continue
                if stat.S_ISDIR(st.st_mode):
                    if st.st_dev != self.dev:      # another filesystem mounted here
                        continue
                    node = self.walk(e.path, e.name)
                    size += node["s"]
                    count += node["k"] + 1
                    subdirs.append(node)
                    continue
                count += 1
                self.files += 1
                if st.st_nlink > 1:
                    key = (st.st_dev, st.st_ino)
                    if key in self.inodes:
                        continue
                    self.inodes.add(key)
                alloc = st.st_blocks * 512
                size += alloc
                self.bytes += alloc
                files.append((alloc, e.name, int(st.st_mtime), "l" if stat.S_ISLNK(st.st_mode) else ""))
        self.progress(path)
        # only the largest files travel up; the rest become one sum
        big = heapq.nlargest(KEEP, files)
        rest = sum(f[0] for f in files) - sum(f[0] for f in big)
        children = subdirs + [{"n": f[1], "s": f[0], "m": f[2], **({"l": True} if f[3] else {})} for f in big]
        node = {"n": name, "s": size, "d": True, "c": children, "k": count}
        if rest:
            node["r"] = rest
        return node


def prune(node, floor):
    """Drop what's too small to see, folding it into the folder's "smaller items"."""
    if not node.get("d"):
        return
    kids = sorted(node["c"], key=lambda c: -c["s"])
    keep, rest = [], node.get("r", 0)
    for c in kids:
        if len(keep) < KEEP and c["s"] >= floor:
            keep.append(c)
            prune(c, floor)
        else:
            rest += c["s"]
    node["c"] = keep
    if rest:
        node["r"] = rest
    else:
        node.pop("r", None)


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "mounts":
        print(json.dumps(mounts()))
    elif cmd == "scan" and len(sys.argv) > 2:
        root = os.path.expanduser(sys.argv[2])
        if not os.path.isdir(root):
            raise SystemExit(json.dumps({"error": f"{root} isn't a folder"}))
        s = Scan(root)
        t0 = time.monotonic()
        tree = s.walk(s.root, s.root)
        prune(tree, max(1, int(tree["s"] * MIN_SHARE)))
        print(json.dumps({"root": s.root, "tree": tree, "files": s.files, "dirs": s.dirs,
                          "errors": s.errors, "seconds": round(time.monotonic() - t0, 1),
                          "at": int(time.time())}, separators=(",", ":")))
    elif cmd == "trash" and len(sys.argv) > 2:
        path = os.path.realpath(sys.argv[2])
        home = os.path.realpath(os.path.expanduser("~"))
        if path in ("/", home) or not os.path.lexists(sys.argv[2]):
            raise SystemExit(json.dumps({"error": "refusing to trash that"}))
        res = subprocess.run(["gio", "trash", "--", sys.argv[2]], capture_output=True, text=True)
        if res.returncode:
            raise SystemExit(json.dumps({"error": (res.stderr.strip().split("\n") or ["Trash failed"])[-1]}))
        print(json.dumps({"ok": True}))
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
