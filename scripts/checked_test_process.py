"""Deadline ownership for a test process and its descendants, with durable output."""
import os
import signal
import subprocess
import time


class TestProcess:
    def __init__(self, timeout, environment):
        self.deadline = time.monotonic() + timeout
        self.environment = environment

    def run(self, command, log, expected_exit_codes=(0,)):
        remaining = self.deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError("Test execution deadline exceeded")
        with open(log, "w", encoding="utf-8") as output:
            process = subprocess.Popen(command, env=self.environment, stdout=output,
                                       stderr=subprocess.STDOUT, start_new_session=True)
            try:
                code = process.wait(timeout=remaining)
            except (subprocess.TimeoutExpired, KeyboardInterrupt):
                self.stop(process)
                raise TimeoutError("Test execution deadline exceeded or was interrupted")
        if code not in expected_exit_codes:
            raise subprocess.CalledProcessError(code, command)
        return code

    @staticmethod
    def stop(process):
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            pass
        # A cooperative parent may have exited while a native child ignored SIGTERM.
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()
