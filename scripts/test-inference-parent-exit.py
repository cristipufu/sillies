"""Verify a packaged helper exits when its caller dies, even while its stdin stays open."""
import os
from pathlib import Path
import select
import signal
import subprocess
import sys
import tempfile
import time


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


def run():
    helper = Path(sys.argv[1]).resolve(strict=True)
    parent_program = """
import os, subprocess, sys, time
child = subprocess.Popen([sys.argv[1]], stdin=0, stdout=subprocess.DEVNULL, stderr=2)
print(child.pid, flush=True)
while True: time.sleep(1)
"""
    child_pid = None
    with tempfile.TemporaryFile() as errors:
        parent = subprocess.Popen(
            [sys.executable, "-c", parent_program, str(helper)],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=errors)
        try:
            if not select.select([parent.stdout], [], [], 5)[0]:
                raise RuntimeError("The caller did not launch its helper within five seconds")
            child_pid = int(parent.stdout.readline())
            time.sleep(0.5)
            if not alive(child_pid):
                raise RuntimeError("The helper exited before the caller")
            parent.kill()
            parent.wait(timeout=5)
            # Keep parent.stdin open: EOF cannot be the reason the helper exits.
            deadline = time.monotonic() + 5
            while alive(child_pid) and time.monotonic() < deadline:
                time.sleep(0.02)
            if alive(child_pid):
                raise RuntimeError("The helper survived its caller")
            print("INFERENCE PARENT EXIT CHECK PASSED: orphaned helper exits with stdin still open")
        finally:
            if parent.poll() is None:
                parent.kill()
                parent.wait(timeout=5)
            if child_pid is not None and alive(child_pid):
                os.kill(child_pid, signal.SIGKILL)
            parent.stdin.close()
            parent.stdout.close()


if __name__ == "__main__":
    try:
        run()
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f"Inference parent exit check failed: {error}", file=sys.stderr)
        sys.exit(1)
