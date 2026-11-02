"""Reject unrelated, duplicated or altered evidence before reporting or resuming a run."""
from __future__ import annotations

import json
import math
from pathlib import Path

from . import corpus, evidence, scoring


def planned_jobs(configuration: dict) -> dict[str, dict]:
    cases = configuration.get("cases")
    if cases is None:
        return {}
    for case in cases:
        corpus.validate(case)
    if corpus.digest(cases) != configuration["corpusHash"]:
        raise ValueError("Frozen corpus does not match its hash")
    jobs = corpus.jobs(cases, configuration["repeats"], configuration.get("orderSeed"))
    expected = {job["id"]: job["profile"] for job in jobs}
    actual = {job["id"]: job["profile"] for job in configuration["jobs"]}
    if actual != expected or list(actual) != list(expected) or len(actual) != len(configuration["jobs"]):
        raise ValueError("Planned jobs do not match the frozen corpus")
    return {job["id"]: job for job in jobs}


def validate(result: dict, job: dict, model: str) -> None:
    expected = {"job": job["id"], "case": job["case"]["id"], "group": job["case"]["group"],
                "profile": job["profile"], "repeat": job["repeat"], "model": model}
    if any(result.get(key) != value for key, value in expected.items()):
        raise ValueError(f"Receipt identity mismatch: {job['id']}")
    if len(result["turns"]) != len(job["case"]["turns"]):
        raise ValueError(f"Receipt turn count mismatch: {job['id']}")
    events = []
    for index, turn in enumerate(result["turns"]):
        validate_turn(turn, job, index)
        events.append({"event": "turn", "payload": turn})
        events.extend({"event": "tool", "payload": call} for call in turn["calls"])
    reproduced = scoring.evaluate(job, events, result.get("error"))
    if reproduced["passed"] != result["passed"] or any(
        actual["checks"] != expected["checks"]
        for actual, expected in zip(result["turns"], reproduced["turns"])
    ):
        raise ValueError(f"Stored checks do not reproduce from evidence: {job['id']}")


def validate_turn(turn: dict, job: dict, index: int) -> None:
    expected = job["case"]["turns"][index]
    position = {"job": job["id"], "turn": index}
    if turn["position"] != position or turn["input"] != expected["user"] or turn["rubric"] != expected["rubric"]:
        raise ValueError(f"Turn does not match the planned question/rubric: {position}")
    if turn["responseHash"] != evidence.response_hash(turn):
        raise ValueError(f"Reply hash mismatch: {position}")
    if "evidenceHash" in turn and turn["evidenceHash"] != evidence.review_hash(turn):
        raise ValueError(f"Evidence hash mismatch: {position}")
    for call in turn["calls"]:
        if call["position"] != position:
            raise ValueError(f"Tool call belongs to a different turn: {position}")
    for key in ("seconds", "firstTextSeconds"):
        value = turn.get(key)
        if value is not None and (not isinstance(value, (float, int)) or not math.isfinite(value) or value < 0):
            raise ValueError(f"Invalid timing: {position}")


def load(output: Path, configuration: dict) -> dict[str, list[dict]]:
    jobs = planned_jobs(configuration)
    profiles = {job["id"]: job["profile"] for job in configuration["jobs"]}
    results = {}
    for model in configuration["models"]:
        cases, seen = [], set()
        for path in sorted((output / model / "cases").glob("*.json")):
            result = json.loads(path.read_text())
            identifier = result["job"]
            if identifier in seen or identifier not in profiles or path.stem != identifier:
                raise ValueError(f"Duplicate or unplanned receipt: {path}")
            if result["model"] != model or result["profile"] != profiles[identifier]:
                raise ValueError(f"Receipt model/profile mismatch: {path}")
            if jobs:
                validate(result, jobs[identifier], model)
            else:
                for turn in result["turns"]:
                    if turn["responseHash"] != evidence.response_hash(turn):
                        raise ValueError(f"Reply hash mismatch: {path}")
            seen.add(identifier)
            cases.append(result)
        results[model] = cases
    return results
