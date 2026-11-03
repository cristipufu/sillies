#!/usr/bin/env python3
"""Bounded, headless checks of stored Chat history and interrupted-write recovery.

Build tests first with scripts/test.sh. All databases are synthetic and isolated;
this command never touches the running app, its settings, or its conversations.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import signal
import subprocess
import sys
import tempfile
import time

from checked_test_process import TestProcess


class ConversationScaleRun:
    SEED_DEADLINE = 180
    TEST_DEADLINE = 120
    TRANSACTION_DEADLINE = 20

    def __init__(self, options):
        self.options = options
        self.output = options.output.resolve()
        self.output.mkdir(parents=True, exist_ok=False)
        self.probe = options.bin_path.resolve() / "ConversationStorageProbe"
        if not self.probe.is_file():
            raise FileNotFoundError(f"Build the ConversationStorageProbe target first: {self.probe}")
        self.report = dict(head=self.git("rev-parse", "HEAD"), status=self.git("status", "--short"),
                           platform=platform.platform(), counts=options.counts, phases=[],
                           artifacts=self.artifact_fingerprints())
        self.save_report()

    @staticmethod
    def git(*arguments):
        return subprocess.check_output(["git", *arguments], text=True).strip()

    def save_report(self):
        (self.output / "summary.json").write_text(json.dumps(self.report, indent=2) + "\n")

    def artifact_fingerprints(self):
        binaries = [self.probe]
        for bundle in ["SilliesVaultTests", "SilliesAppTests"]:
            binaries.append(self.options.bin_path / f"{bundle}.xctest/Contents/MacOS/{bundle}")
        result = {}
        for binary in binaries:
            digest = hashlib.sha256()
            with binary.open("rb") as source:
                for chunk in iter(lambda: source.read(1_048_576), b""):
                    digest.update(chunk)
            result[binary.name] = digest.hexdigest()
        return result

    def run(self):
        for count in self.options.counts:
            directory = Path(tempfile.mkdtemp(prefix=f"sillies-stored-{count}-"))
            self.report.setdefault("databases", []).append(str(directory))
            self.save_report()
            try:
                self.check_history(directory, count)
            except BaseException:
                print(f"Preserved synthetic database for diagnosis: {directory}", flush=True)
                raise
            if not self.options.keep_databases:
                shutil.rmtree(directory)
        self.report["complete"] = True
        self.save_report()

    def check_history(self, directory, count):
        self.command(f"{count}-seed", [str(self.probe), "seed", str(directory), str(count)],
                     self.SEED_DEADLINE, dict(os.environ), [f"SEEDED {count} messages"])
        self.native_tests(f"{count}-storage", "SILLIES_STORED_HISTORY_DIRECTORY", directory,
                          ["SilliesVaultTests.growingStoredHistory.*"], [f"STORED HISTORY {count}:"])
        self.native_tests(f"{count}-interface", "SILLIES_STORED_HISTORY_DIRECTORY", directory,
                          ["SilliesAppTests.storedChatPages.*"], [f"HEADLESS CHAT {count}:"])
        self.kill_during_transaction(directory, count)
        self.native_tests(f"{count}-recovery", "SILLIES_RECOVERY_DIRECTORY", directory,
                          ["SilliesVaultTests.killedWriter.*"], ["RECOVERY VERIFIED:"])

    def native_tests(self, name, variable, directory, filters, markers):
        command = [sys.executable, "-B", "scripts/run-checked-tests.py", "--bin-path",
                   str(self.options.bin_path.resolve()), "--framework", "swift-testing",
                   "--timeout", str(self.TEST_DEADLINE)]
        for selection in filters:
            command.extend(["--filter", selection])
        environment = dict(os.environ)
        environment.pop("SILLIES_STORED_HISTORY_DIRECTORY", None)
        environment.pop("SILLIES_RECOVERY_DIRECTORY", None)
        environment[variable] = str(directory)
        self.command(name, command, self.TEST_DEADLINE + 30, environment,
                     markers + ["Verified completion of"])

    def command(self, name, command, timeout, environment, markers):
        log = self.output / f"{name}.log"
        started = time.monotonic()
        print(f"Starting {name}", flush=True)
        phase = dict(name=name, command=command, log=log.name)
        self.report["phases"].append(phase)
        try:
            TestProcess(timeout, environment).run(command, log)
            output = log.read_text()
            for marker in markers:
                if marker not in output:
                    raise RuntimeError(f"Missing completion marker {marker!r}; see {log}")
            phase["passed"] = True
        finally:
            phase["elapsed_seconds"] = time.monotonic() - started
            self.save_report()
        print(f"Passed {name} ({phase['elapsed_seconds']:.2f}s)", flush=True)

    def kill_during_transaction(self, directory, count):
        name = f"{count}-kill-writer"
        marker = directory / "transaction-open"
        if marker.exists():
            raise RuntimeError("Refusing a stale interrupted-transaction marker")
        log = self.output / f"{name}.log"
        with log.open("w") as output:
            process = subprocess.Popen([str(self.probe), "hold-transaction", str(directory)],
                                       stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
            try:
                self.wait_for_transaction(process, marker)
                wal = directory / "conversations.sqlite-wal"
                wal_bytes = wal.stat().st_size
                if wal_bytes == 0:
                    raise RuntimeError("Fault injection did not produce an uncommitted WAL")
                os.killpg(process.pid, signal.SIGKILL)
                code = process.wait(timeout=5)
                if code != -signal.SIGKILL:
                    raise RuntimeError(f"Expected SIGKILL, received {code}")
                self.report["phases"].append(dict(name=name, exit_code=code, wal_bytes=wal_bytes,
                                                   log=log.name, passed=True))
                self.save_report()
                print(f"Interrupted writer for {count} messages with SIGKILL ({wal_bytes} WAL bytes)",
                      flush=True)
            finally:
                if process.poll() is None:
                    TestProcess.stop(process)

    def wait_for_transaction(self, process, marker):
        deadline = time.monotonic() + self.TRANSACTION_DEADLINE
        while time.monotonic() < deadline:
            if process.poll() is not None:
                raise RuntimeError("Writer exited before the interruption marker")
            if marker.is_file():
                return
            time.sleep(0.02)
        raise TimeoutError("Writer never reached the uncommitted transaction")


def history_count(value):
    count = int(value)
    if not 10_000 <= count <= 1_000_000:
        raise argparse.ArgumentTypeError("History count must be between 10,000 and 1,000,000")
    return count


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bin-path", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path, help="New evidence directory")
    parser.add_argument("--counts", nargs="+", type=history_count, default=[100_000, 1_000_000])
    parser.add_argument("--keep-databases", action="store_true")
    options = parser.parse_args()
    try:
        ConversationScaleRun(options).run()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError, TimeoutError) as error:
        print(f"Conversation scale validation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
