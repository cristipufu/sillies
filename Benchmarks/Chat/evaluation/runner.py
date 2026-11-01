"""Process supervision: native hangs cannot block a batch or erase an unfinished case."""
from __future__ import annotations

import json
import os
import selectors
import signal
import subprocess
import tempfile
import time
from pathlib import Path

from .corpus import worker_job
from .scoring import evaluate
from .storage import record_model_metadata, write_json

MAX_EVENT_BYTES = 8 * 1024 * 1024


class Worker:
    def __init__(self, command: list[str], stderr: Path):
        self.log = stderr.open("ab")
        self.process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=self.log, start_new_session=True, bufsize=0)
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.process.stdout, selectors.EVENT_READ)
        self.buffer = bytearray()

    def receive(self, timeout: float = 0.2) -> list[dict]:
        events = []
        for key, _ in self.selector.select(timeout):
            data = os.read(key.fd, 65536)
            if not data:
                self.selector.unregister(key.fileobj)
                continue
            self.buffer.extend(data)
            if len(self.buffer) > MAX_EVENT_BYTES:
                raise ValueError("Worker event exceeded the bounded protocol size")
            while b"\n" in self.buffer:
                line, _, remainder = self.buffer.partition(b"\n")
                self.buffer = bytearray(remainder)
                events.append(json.loads(line))
        return events

    def admit(self) -> None:
        self.process.stdin.write(b"next\n")
        self.process.stdin.flush()

    def finish(self) -> None:
        if not self.process.stdin.closed:
            self.process.stdin.close()

    def close(self) -> None:
        self.finish()
        try:
            self.process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            self._signal(signal.SIGTERM)
            try:
                self.process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self._signal(signal.SIGKILL)
                self.process.wait(timeout=2)
        self.selector.close()
        self.process.stdout.close()
        self.log.close()

    def _signal(self, value: int) -> None:
        try:
            os.killpg(self.process.pid, value)
        except ProcessLookupError:
            pass


class ModelBatch:
    def __init__(self, options, model: str, jobs: list[dict], deadline: float):
        self.options = options
        self.model = model
        self.directory = options.output / model
        self.directory.mkdir(parents=True, exist_ok=True)
        self.jobs = [job for job in jobs if not (self.directory / "cases" / f"{job['id']}.json").exists()]
        self.deadline = deadline
        self.current: dict | None = None
        self.events: list[dict] = []
        self.case_deadline = float("inf")
        self.turn_deadline = time.monotonic() + options.startup_timeout
        self.seen_turns: set[int] = set()

    def run(self) -> None:
        interrupted = 0
        while self.jobs and time.monotonic() < self.deadline and interrupted < 3:
            failure = self._attempt()
            if failure:
                interrupted += 1
                if self.current:
                    self._complete(failure)
                else:
                    write_json(self.directory / "startup-failure.json", {"error": failure})
                    return

    def _attempt(self) -> str | None:
        with tempfile.TemporaryDirectory(prefix="sillies-benchmark-") as workspace:
            plan = {"model": self.model, "modelDirectory": str(self.options.models_root),
                    "helper": str(self.options.helper), "workspace": workspace,
                    "jobs": [worker_job(job) for job in self.jobs]}
            plan_path = Path(workspace) / "plan.json"
            write_json(plan_path, plan)
            worker = Worker([str(self.options.worker), str(plan_path)], self.directory / "worker.stderr.log")
            self.turn_deadline = time.monotonic() + self.options.startup_timeout
            try:
                return self._consume(worker)
            except (ValueError, KeyError, TypeError, OSError) as error:
                return f"Worker protocol failed: {error}"
            finally:
                worker.close()

    def _consume(self, worker: Worker) -> str | None:
        stopping = False
        with (self.directory / "events.jsonl").open("a") as log:
            while True:
                for event in worker.receive():
                    log.write(json.dumps(event, ensure_ascii=False) + "\n")
                    log.flush()
                    kind, payload = event["event"], event["payload"]
                    if kind == "model":
                        record_model_metadata(self.directory / "model.json", payload)
                        worker.admit()
                    elif kind == "caseStarted":
                        if self.current is not None or payload["id"] != self.jobs[0]["id"]:
                            raise ValueError("Unexpected or duplicate case start")
                        self.current, self.events = self.jobs[0], [event]
                        self.seen_turns = set()
                        self.case_deadline = time.monotonic() + self.options.case_timeout
                        print(f"{self.model} · {self.current['id']}", flush=True)
                    elif kind == "caseFinished":
                        self._require_job(payload["job"])
                        self.events.append(event)
                        self._complete(payload.get("error"))
                        if self.jobs and time.monotonic() < self.deadline:
                            worker.admit()
                        else:
                            stopping = True
                            worker.finish()
                            self.turn_deadline = time.monotonic() + 10
                    elif kind in {"turnStarted", "tool", "turn"}:
                        position = payload if kind == "turnStarted" else payload["position"]
                        self._require_job(position["job"])
                        index = position["turn"]
                        if not isinstance(index, int) or not 0 <= index < len(self.current["case"]["turns"]):
                            raise ValueError("Invalid turn index")
                        if kind == "turnStarted":
                            self.turn_deadline = time.monotonic() + self.options.turn_timeout
                        if kind == "turn":
                            if index in self.seen_turns:
                                raise ValueError("Duplicate turn result")
                            self.seen_turns.add(index)
                        self.events.append(event)
                    else:
                        raise ValueError(f"Unknown worker event: {kind}")
                if worker.process.poll() is not None and not worker.selector.get_map():
                    if worker.buffer:
                        return "Worker exited with an incomplete event"
                    if self.current:
                        return f"Worker exited before completing the case (status {worker.process.returncode})"
                    return None if stopping or not self.jobs else f"Worker exited early (status {worker.process.returncode})"
                if time.monotonic() > min(self.case_deadline, self.turn_deadline):
                    return None if stopping else "Native evaluation exceeded its process deadline"

    def _require_job(self, identifier: str) -> None:
        if self.current is None or self.current["id"] != identifier:
            raise ValueError("Event does not belong to the current case")

    def _complete(self, failure: str | None) -> None:
        result = evaluate(self.current, self.events, failure)
        result["model"] = self.model
        write_json(self.directory / "cases" / f"{self.current['id']}.json", result)
        print(f"  {'PASS' if result['passed'] else 'FAIL'} · {len(result['turns'])} turns", flush=True)
        self.jobs.pop(0)
        self.current, self.events = None, []
        self.case_deadline = float("inf")
        self.turn_deadline = time.monotonic() + self.options.startup_timeout
