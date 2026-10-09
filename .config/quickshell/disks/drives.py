#!/usr/bin/env python3
"""Removable drives for Drives.qml (after Wian47/omarchy-removable-drives).

    drives.py list               JSON: [{ drive..., volumes: [...] }]
    drives.py mount DEV          mount a volume (udisks, no password)
    drives.py unmount DEV        unmount; on "busy" says who holds it
    drives.py unmount-lazy DEV   detach now, finish when the holders let go
    drives.py unlock DEV         passphrase on stdin; mounts what it opens
    drives.py lock DEV           unmount what's inside, close the container
    drives.py eject DRIVE        unmount every volume, lock, power the drive off

Everything goes through udisksctl, which lets the active session do this
without root. A drive holding /, /boot, /home or swap is never listed, even
when it reports itself removable (a USB-booted system disk does).
DRIVES_FAKE=file.json (or ~/.cache/quickshell/drives-fake.json) stands in for lsblk,
for testing the UI without a stick.
"""

import json
import os
import re
import subprocess
import sys

SYSTEM = {"/", "/boot", "/boot/efi", "/efi", "/home", "/usr", "/var", "[SWAP]"}
DEV = re.compile(r"^/dev/[A-Za-z0-9/_.:-]{1,64}$")
LSBLK = ["lsblk", "-J", "-b", "-o", "NAME,PATH,TYPE,RM,HOTPLUG,TRAN,MODEL,VENDOR,SERIAL,SIZE,FSTYPE,"
         "LABEL,UUID,MOUNTPOINTS,FSAVAIL,FSUSE%,PKNAME,RO,STATE"]


def run(*args, stdin=None):
    return subprocess.run(args, input=stdin, capture_output=True, text=True)


def mountpoints(node):
    return [m for m in (node.get("mountpoints") or []) if m]


def walk(node):
    yield node
    for child in node.get("children") or []:
        yield from walk(child)


def disk_stat(name):
    """(writes in flight, sectors written so far) from sysfs."""
    try:
        inflight = open(f"/sys/block/{name}/inflight").read().split()
        stat = open(f"/sys/block/{name}/stat").read().split()
        return int(inflight[1]), int(stat[6])
    except (OSError, IndexError, ValueError):
        return 0, 0


def volume(node, parent):
    v = {
        "name": node["name"], "path": node["path"], "fstype": node.get("fstype") or "",
        "label": node.get("label") or "", "size": node.get("size") or 0,
        "mountpoint": (mountpoints(node) or [""])[0], "avail": node.get("fsavail"),
        "use": node.get("fsuse%"), "readonly": bool(node.get("ro")),
        "crypto": node.get("fstype") == "crypto_LUKS", "locked": False, "cleartext": "",
    }
    if v["crypto"]:
        inner = (node.get("children") or [None])[0]
        v["locked"] = inner is None
        if inner:
            v["cleartext"] = inner["path"]
            v["mountpoint"] = (mountpoints(inner) or [""])[0]
            v["avail"], v["use"] = inner.get("fsavail"), inner.get("fsuse%")
            v["innerFstype"] = inner.get("fstype") or ""
    return v


def list_drives():
    fake = os.environ.get("DRIVES_FAKE") or next(
        (f for f in [os.path.expanduser("~/.cache/quickshell/drives-fake.json")] if os.path.exists(f)), None)
    data = json.load(open(fake)) if fake else json.loads(run(*LSBLK).stdout or '{"blockdevices": []}')
    out = []
    for disk in data.get("blockdevices", []):
        if disk.get("type") != "disk":
            continue
        removable = disk.get("rm") or disk.get("hotplug") or disk.get("tran") in ("usb", "mmc", "ieee1394")
        if not removable and not fake:
            continue
        if any(set(mountpoints(n)) & SYSTEM for n in walk(disk)):
            continue
        parts = [c for c in disk.get("children") or [] if c.get("type") in ("part", "crypt")]
        # a stick formatted without a partition table is its own volume
        vols = [volume(p, disk) for p in parts] if parts else ([volume(disk, disk)] if disk.get("fstype") else [])
        writing, sectors = disk_stat(disk["name"])
        if fake:
            writing, sectors = disk.get("_writing", 0), disk.get("_sectors", 0)
        name = " ".join(x for x in ((disk.get("vendor") or "").strip(), (disk.get("model") or "").strip()) if x)
        out.append({
            "name": disk["name"], "path": disk["path"], "title": name or disk["name"],
            "tran": disk.get("tran") or "", "size": disk.get("size") or 0,
            "serial": disk.get("serial") or "", "writing": writing, "sectorsWritten": sectors,
            "volumes": [v for v in vols if v["fstype"] or v["crypto"]],
        })
    return out


def holders(path, mountpoint):
    """Process names keeping a mount busy."""
    target = mountpoint or path
    res = run("fuser", "-vm", target)
    names = []
    for line in (res.stderr + res.stdout).splitlines()[1:]:
        parts = line.split()
        if len(parts) >= 2 and parts[-1] not in names and not parts[-1].startswith("/"):
            names.append(parts[-1])
    return names


def fail(msg, **extra):
    print(json.dumps({"ok": False, "error": msg, **extra}))
    sys.exit(1)


def ok(**extra):
    print(json.dumps({"ok": True, **extra}))


def find_volume(dev):
    for d in list_drives():
        for v in d["volumes"]:
            if dev in (v["path"], v["cleartext"]):
                return d, v
    fail(f"{dev} isn't a removable volume")


def unmount(dev, lazy=False):
    _, v = find_volume(dev)
    target = v["cleartext"] or v["path"]
    if not v["mountpoint"]:
        return
    if lazy:
        res = run("umount", "-l", v["mountpoint"])
    else:
        res = run("udisksctl", "unmount", "-b", target, "--no-user-interaction")
    if res.returncode:
        err = (res.stderr or res.stdout).strip()
        if "busy" in err.lower():
            fail("busy", holders=holders(target, v["mountpoint"]), device=dev)
        fail(err.split("\n")[-1])


def main():
    args = sys.argv[1:]
    cmd = args[0] if args else "list"
    if cmd == "list":
        print(json.dumps(list_drives()))
        return
    if len(args) < 2 or not DEV.match(args[1]):
        fail("drives.py " + cmd + " /dev/…")
    dev = args[1]
    if cmd == "mount":
        _, v = find_volume(dev)
        target = v["cleartext"] or v["path"]
        res = run("udisksctl", "mount", "-b", target, "--no-user-interaction")
        if res.returncode:
            fail((res.stderr or res.stdout).strip().split("\n")[-1])
        _, v = find_volume(dev)
        ok(mountpoint=v["mountpoint"])
    elif cmd in ("unmount", "unmount-lazy"):
        unmount(dev, lazy=cmd == "unmount-lazy")
        ok()
    elif cmd == "unlock":
        secret = sys.stdin.read().rstrip("\n")
        res = run("udisksctl", "unlock", "-b", dev, "--key-file", "/dev/stdin", "--no-user-interaction", stdin=secret)
        if res.returncode:
            fail("Wrong passphrase" if "passphrase" in (res.stderr or "").lower() or "keyslot" in (res.stderr or "").lower()
                 else (res.stderr or res.stdout).strip().split("\n")[-1])
        _, v = find_volume(dev)
        if v["cleartext"]:
            run("udisksctl", "mount", "-b", v["cleartext"], "--no-user-interaction")
        ok()
    elif cmd == "lock":
        unmount(dev)
        res = run("udisksctl", "lock", "-b", dev, "--no-user-interaction")
        if res.returncode:
            fail((res.stderr or res.stdout).strip().split("\n")[-1])
        ok()
    elif cmd == "eject":
        drive = next((d for d in list_drives() if d["path"] == dev), None)
        if not drive:
            fail(f"{dev} isn't a removable drive")
        for v in drive["volumes"]:
            unmount(v["path"])
            if v["crypto"] and not v["locked"]:
                run("udisksctl", "lock", "-b", v["path"], "--no-user-interaction")
        run("sync")
        res = run("udisksctl", "power-off", "-b", dev, "--no-user-interaction")
        # some card readers can't be powered off; unmounted is still safe to pull
        ok(poweredOff=res.returncode == 0)
    else:
        fail("unknown command " + cmd)


if __name__ == "__main__":
    main()
