#!/usr/bin/env python3
"""Measure key-to-frame latency of the M1 executable on a PTY.

The probe starts ``build/exec/lambda-rogue`` in an 80x24 pseudo-terminal,
waits for the initial frame, then alternates ``l`` and ``h`` so every key
is a valid move.  A frame is complete when termui emits the cursor-hide
sequence ``ESC[?25l``.  The measured time includes the PTY, the Python
reader, and the game's own input-to-redraw path; it is not a pure kernel
input timestamp.

Run from the repository root after ``./verify.sh`` or a build::

    python3 tests/latency_probe.py

The numbers are printed, not asserted.  See ``doc/m1-measurements.md``
for the development-host record.
"""

import fcntl
import os
import pty
import select
import statistics
import struct
import subprocess
import sys
import termios
import time

EXE = "./build/exec/lambda-rogue"
SAMPLES = 50
FRAME_END = b"\x1b[?25l"


def drain(master):
    while select.select([master], [], [], 0)[0]:
        try:
            if not os.read(master, 65536):
                return
        except OSError:
            return


def read_until(master, pattern, timeout=5.0):
    buf = b""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        ready, _, _ = select.select([master], [], [], 0.05)
        if not ready:
            continue
        try:
            chunk = os.read(master, 65536)
        except OSError:
            return buf, None
        if not chunk:
            return buf, None
        buf += chunk
        if pattern in buf:
            return buf, time.monotonic()
    return buf, None


def main():
    master, slave = pty.openpty()
    fcntl.ioctl(
        slave,
        termios.TIOCSWINSZ,
        struct.pack("HHHH", 24, 80, 0, 0),
    )
    env = dict(os.environ, TERM="xterm-256color")
    proc = subprocess.Popen(
        [EXE],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        close_fds=True,
        env=env,
    )
    os.close(slave)

    _, started = read_until(master, b"Turn 0")
    if started is None:
        print("startup timeout", file=sys.stderr)
        proc.kill()
        return 1
    time.sleep(0.2)
    drain(master)

    samples = []
    for i in range(1, SAMPLES + 1):
        key = b"l" if i % 2 == 1 else b"h"
        t0 = time.monotonic()
        os.write(master, key)
        _, finished = read_until(master, FRAME_END)
        if finished is None:
            print("timeout at turn %d" % i, file=sys.stderr)
            break
        samples.append((finished - t0) * 1000.0)

    os.write(master, b"q")
    time.sleep(0.2)
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
    os.close(master)

    if not samples:
        return 1

    ordered = sorted(samples)
    p95 = ordered[min(len(ordered) - 1, int(len(ordered) * 0.95))]
    print("samples:", len(samples))
    print("min: %.2f ms" % ordered[0])
    print("median: %.2f ms" % statistics.median(ordered))
    print("mean: %.2f ms" % statistics.mean(ordered))
    print("p95: %.2f ms" % p95)
    print("max: %.2f ms" % ordered[-1])
    return 0


if __name__ == "__main__":
    sys.exit(main())
