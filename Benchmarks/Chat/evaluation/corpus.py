"""Validate fixtures and remove gold data before constructing worker plans."""
from __future__ import annotations

import hashlib
import json
import random
import re
from pathlib import Path

PROFILES = {"none": 0, "search": 1, "personal": 3, "app": 5, "expanded8": 8, "expanded12": 12}
KINDS = {"reply_equals", "contains_any", "contains_all", "omits_all", "no_tools",
         "required_tools", "allowed_tools", "no_writes", "argument_equals", "memory_contains",
         "memory_absent", "source_includes", "compacted", "retained_context_omits", "compaction_calls_at_most"}
OWNER = {"id": "pogo", "name": "Pogo", "personality": "Warm, curious and upbeat."}
IDENTIFIER = re.compile(r"[a-z][a-z0-9-]{0,90}\Z")


def digest(value: object) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False).encode()).hexdigest()


def load(directory: Path) -> list[dict]:
    cases = []
    for path in sorted(directory.glob("*.json")):
        document = json.loads(path.read_text())
        if document.get("version") != 1 or not isinstance(document.get("cases"), list):
            raise ValueError(f"Invalid corpus version or cases: {path}")
        cases.extend(validate(case) for case in document["cases"])
    if not cases or len({case["id"] for case in cases}) != len(cases):
        raise ValueError("The corpus must have nonempty, unique case IDs")
    return cases


def validate(case: dict) -> dict:
    if not IDENTIFIER.fullmatch(case.get("id", "")) or not IDENTIFIER.fullmatch(case.get("group", "")):
        raise ValueError(f"Invalid case identity: {case.get('id')}")
    if not isinstance(case.get("turns"), list) or not 1 <= len(case["turns"]) <= 20:
        raise ValueError(f"Invalid turn count: {case['id']}")
    if not case.get("profiles") or any(profile not in PROFILES for profile in case["profiles"]):
        raise ValueError(f"Invalid tool profiles: {case['id']}")
    if len(set(case["profiles"])) != len(case["profiles"]):
        raise ValueError(f"Duplicate tool profiles: {case['id']}")
    for turn in case["turns"]:
        if not isinstance(turn.get("user"), str) or not 0 < len(turn["user"]) <= 2000:
            raise ValueError(f"Invalid user message: {case['id']}")
        if not isinstance(turn.get("rubric"), str) or not turn["rubric"].strip():
            raise ValueError(f"Missing semantic rubric: {case['id']}")
        for check in turn.get("checks", []):
            if check.get("kind") not in KINDS:
                raise ValueError(f"Unknown check: {check}")
            if check["kind"] not in {"no_tools", "no_writes", "compacted"}:
                if not isinstance(check.get("values"), list) or not check["values"]:
                    raise ValueError(f"Missing expected values: {check}")
                if not all(isinstance(value, str) for value in check["values"]):
                    raise ValueError(f"Expected values must be strings: {check}")
            if check["kind"] == "compaction_calls_at_most":
                if len(check["values"]) != 1 or not check["values"][0].isdigit() or not 0 <= int(check["values"][0]) <= 200:
                    raise ValueError(f"Invalid compaction call bound: {check}")
            if check["kind"] == "argument_equals" and not all(check.get(key) for key in ("tool", "field")):
                raise ValueError(f"Argument checks need a tool and field: {check}")
    batches = case.get("historyBatches", [])
    if not isinstance(batches, list) or len(batches) > len(case["turns"]):
        raise ValueError(f"Invalid incremental history: {case['id']}")
    if any(not isinstance(batch, list) or len(batch) > 100 for batch in batches):
        raise ValueError(f"Invalid incremental history batch: {case['id']}")
    for message in case.get("history", []) + [item for batch in batches for item in batch]:
        if message.get("role") not in {"user", "assistant"} or not isinstance(message.get("text"), str):
            raise ValueError(f"Invalid seeded history: {case['id']}")
    if len(case.get("history", [])) > 200:
        raise ValueError(f"Seeded history is too large: {case['id']}")
    return case


def jobs(cases: list[dict], repeats: int, order_seed: int | None = None) -> list[dict]:
    result = []
    for repeat in range(1, repeats + 1):
        batch = [{"id": f"{case['id']}--{profile}--r{repeat}", "case": case, "profile": profile, "repeat": repeat}
                 for case in cases for profile in case["profiles"]]
        if order_seed is not None:
            random.Random(order_seed + repeat).shuffle(batch)
        result.extend(batch)
    return result


def worker_job(job: dict) -> dict:
    case = job["case"]
    scenario = {"id": case["id"], "owner": case.get("owner", OWNER), "language": case.get("language", "en"),
                "history": case.get("history", []), "historyBatches": case.get("historyBatches", []), "records": case.get("records", []),
                "memories": case.get("memories", []), "turns": [turn["user"] for turn in case["turns"]]}
    return {"id": job["id"], "scenario": scenario, "tools": job["profile"]}
