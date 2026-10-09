#!/usr/bin/env python3
"""Internet speed test for Settings > Network, using Cloudflare's speed endpoints.

Prints one JSON object per phase as it finishes, so the page can fill in as it
goes:  {"ping": ms}  {"down": bits/s}  {"up": bits/s}  {"done": true}
or {"error": "..."} if a phase could not run at all.

Several curl streams run in parallel, because one TCP stream rarely fills a
fast line; each is capped in time, and the rate is total bytes over the wall
clock of the whole phase.
"""

import json
import os
import statistics
import subprocess
import sys
import tempfile
import threading
import time

BASE = "https://speed.cloudflare.com"
STREAMS = 4
SECONDS = 6            # length of each phase
DOWN_BYTES = 25_000_000
UP_BYTES = 10_000_000


def emit(**item):
    print(json.dumps(item), flush=True)


def curl(*args, limit=SECONDS):
    return ["curl", "-s", "-o", "/dev/null", "--max-time", f"{limit:.1f}", *args]


def ping():
    """Median TCP handshake time: one round trip, without server processing."""
    samples = []
    for _ in range(6):
        out = subprocess.run(
            curl("-w", "%{time_namelookup} %{time_connect}", f"{BASE}/__down?bytes=0"),
            capture_output=True, text=True).stdout.split()
        if len(out) == 2 and float(out[1]) > 0:
            samples.append((float(out[1]) - float(out[0])) * 1000)
    return statistics.median(samples) if samples else None


def parallel(command):
    """Each stream repeats `command` until the window closes; bytes over wall time.

    Cloudflare refuses single requests above ~50 MB, so a fast line needs
    several requests per stream to stay busy for the whole window.
    """
    start = time.monotonic()
    deadline = start + SECONDS
    total = [0.0]
    lock = threading.Lock()

    def stream():
        while True:
            left = deadline - time.monotonic()
            if left < 0.2:
                return
            out = subprocess.run(command(left), capture_output=True, text=True).stdout.split()
            with lock:
                total[0] += float(out[0]) if out else 0
            if not out or float(out[0]) == 0:
                return

    workers = [threading.Thread(target=stream) for _ in range(STREAMS)]
    for worker in workers:
        worker.start()
    for worker in workers:
        worker.join()
    elapsed = time.monotonic() - start
    return total[0] * 8 / elapsed if total[0] > 0 else None


def main():
    latency = ping()
    if latency is None:
        emit(error="Could not reach speed.cloudflare.com")
        return 1
    emit(ping=round(latency, 1))

    down = parallel(lambda left: curl("-w", "%{size_download}", f"{BASE}/__down?bytes={DOWN_BYTES}", limit=left))
    emit(down=down)

    with tempfile.NamedTemporaryFile(dir=os.environ.get("XDG_RUNTIME_DIR")) as blob:
        blob.write(os.urandom(UP_BYTES))
        blob.flush()
        up = parallel(lambda left: curl("-w", "%{size_upload}", "-H", "Content-Type: application/octet-stream",
                                        "--data-binary", f"@{blob.name}", f"{BASE}/__up", limit=left))
    emit(up=up)
    emit(done=True, at=int(time.time()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
