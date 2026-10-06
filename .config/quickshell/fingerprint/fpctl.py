#!/usr/bin/env python3
"""Talk to fprintd over D-Bus for Settings > Fingerprint (Fingerprint.qml).

    fpctl.py list                 enrolled fingers + device info
    fpctl.py enroll <finger>      live enroll progress
    fpctl.py verify [finger]      one verify attempt (default: any finger)
    fpctl.py delete <finger>      delete one finger
    fpctl.py delete-all           delete every finger of this user

Prints one JSON object per line (flushed), always ending with {"ev": "end"}.
Enrolling/deleting ask polkit for your password (Auth.qml shows the prompt).
Exits, releasing the reader, if Quickshell (the parent) goes away.
"""
import json, os, signal, sys
from gi.repository import Gio, GLib
try:
    from gi.repository import GLibUnix
    signal_add = GLibUnix.signal_add
except ImportError:
    signal_add = GLib.unix_signal_add

BUS = "net.reactivated.Fprint"
DEV_IF = "net.reactivated.Fprint.Device"
FOREVER = GLib.MAXINT  # polkit prompts can take a while

def out(**kw):
    print(json.dumps(kw), flush=True)

def err_name(e):
    return Gio.DBusError.get_remote_error(e) or ""

def short(e):
    name = err_name(e).rsplit(".", 1)[-1]
    return name, e.message.split(": ", 1)[-1] if e.message.startswith("GDBus.Error:") else e.message

bus = Gio.bus_get_sync(Gio.BusType.SYSTEM)
loop = GLib.MainLoop()
claimed = False
dev = None
running = None  # "enroll" / "verify"

def call(proxy, method, sig=None, args=(), timeout=FOREVER):
    return proxy.call_sync(method, GLib.Variant(sig, args) if sig else None,
                           Gio.DBusCallFlags.ALLOW_INTERACTIVE_AUTHORIZATION, timeout, None)

def device():
    mgr = Gio.DBusProxy.new_sync(bus, 0, None, BUS, "/net/reactivated/Fprint/Manager",
                                 "net.reactivated.Fprint.Manager", None)
    path = call(mgr, "GetDefaultDevice", timeout=5000).unpack()[0]
    return Gio.DBusProxy.new_sync(bus, 0, None, BUS, path, DEV_IF, None)

def prop(name, default=None):
    v = dev.get_cached_property(name)
    return v.unpack() if v is not None else default

def cleanup():
    global claimed
    if running:
        try: call(dev, "EnrollStop" if running == "enroll" else "VerifyStop", timeout=3000)
        except GLib.Error: pass
    if claimed:
        try: call(dev, "Release", timeout=3000)
        except GLib.Error: pass
        claimed = False

def finish(code=0):
    cleanup()
    out(ev="end")
    os._exit(code)  # also from inside GLib callbacks, where SystemExit gets swallowed

def fail(e, stage):
    name, msg = short(e)
    out(ev="error", stage=stage, name=name, msg=msg)
    finish(1)

def claim():
    global claimed
    try:
        call(dev, "Claim", "(s)", ("",))
        claimed = True
    except GLib.Error as e:
        fail(e, "claim")

def list_fingers():
    try:
        return list(call(dev, "ListEnrolledFingers", "(s)", ("",), 5000).unpack()[0])
    except GLib.Error as e:
        if err_name(e).endswith("NoEnrolledPrints"):
            return []
        raise

def on_signal(_p, _sender, signame, params):
    res, done = params.unpack()[:2]
    if signame == "EnrollStatus":
        out(ev="enroll", result=res, done=done)
    elif signame == "VerifyStatus":
        out(ev="verify", result=res, done=done)
    elif signame == "VerifyFingerSelected":
        out(ev="finger", finger=res)
        return
    else:
        return
    if done:
        global running
        running = None
        GLib.idle_add(lambda: finish(0 if res in ("enroll-completed", "verify-match") else 2))

def parent_gone():
    if os.getppid() == 1:
        finish(3)
    return True

def main():
    global dev, running
    if len(sys.argv) < 2:
        print(__doc__); sys.exit(64)
    cmd, arg = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else None)
    for s in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal_add(GLib.PRIORITY_HIGH, s, lambda: finish(130))
    GLib.timeout_add_seconds(2, parent_gone)

    try:
        dev = device()
    except GLib.Error as e:
        fail(e, "device")

    if cmd == "list":
        try:
            fingers = list_fingers()
        except GLib.Error as e:
            fail(e, "list")
        out(ev="list", fingers=fingers, name=prop("name", ""), stages=prop("num-enroll-stages", 0),
            scanType=prop("scan-type", "press"))
        finish()

    claim()
    if cmd == "delete":
        try: call(dev, "DeleteEnrolledFinger", "(s)", (arg,))
        except GLib.Error as e: fail(e, "delete")
        out(ev="deleted", finger=arg)
        finish()
    if cmd == "delete-all":
        try: call(dev, "DeleteEnrolledFingers2")
        except GLib.Error as e: fail(e, "delete")
        out(ev="deleted", finger="all")
        finish()

    dev.connect("g-signal", on_signal)
    if cmd == "enroll":
        out(ev="start", finger=arg, stages=prop("num-enroll-stages", 0))
        # re-enrolling: drop the old print first (same claim, so one password prompt)
        try:
            if arg in list_fingers():
                call(dev, "DeleteEnrolledFinger", "(s)", (arg,))
        except GLib.Error as e:
            fail(e, "delete")
        try: call(dev, "EnrollStart", "(s)", (arg,))
        except GLib.Error as e: fail(e, "enroll")
        running = "enroll"
    elif cmd == "verify":
        try: call(dev, "VerifyStart", "(s)", (arg or "any",))
        except GLib.Error as e: fail(e, "verify")
        running = "verify"
        out(ev="start", finger=arg or "any")
    else:
        print(__doc__); finish(64)
    loop.run()

if __name__ == "__main__":
    main()
