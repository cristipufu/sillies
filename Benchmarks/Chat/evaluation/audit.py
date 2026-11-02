"""Recompute a published snapshot without inference or alteration of the original evidence."""
from __future__ import annotations

import gzip
import json
from pathlib import Path

from . import corpus, receipts, report, reviews
from .storage import file_hash


def read_document(path: Path):
    data = path.read_bytes()
    return json.loads(gzip.decompress(data) if path.suffix == ".gz" else data)


def verify(archive: Path, snapshot: Path | None = None) -> dict:
    document = read_document(archive)
    configuration = document["configuration"]
    cases = configuration.get("cases")
    if cases is None:
        if snapshot is None:
            raise ValueError("This legacy archive needs its frozen --corpus-snapshot")
        cases = read_document(snapshot)
    jobs = receipts.planned_jobs({**configuration, "cases": cases})
    if set(document["models"]) != set(configuration["models"]):
        raise ValueError("Archive models differ from the run plan")
    results = {model: value["cases"] for model, value in document["models"].items()}
    semantic = reviews.summarize(document.get("reviews", []), results)
    findings = {}
    for model, recorded in results.items():
        seen = set()
        for receipt in recorded:
            identifier = receipt["job"]
            if identifier not in jobs or identifier in seen:
                raise ValueError(f"Unplanned or duplicate receipt: {model}/{identifier}")
            receipts.validate(receipt, jobs[identifier], model)
            seen.add(identifier)
        primary = [receipt for receipt in recorded if receipt["profile"] == "app"]
        calculated = report.aggregate(primary)
        if calculated != document["summary"]["models"][model]["primary"]:
            raise ValueError(f"Published primary metrics do not reproduce: {model}")
        findings[model] = {"completedCases": len(recorded), "plannedCases": len(jobs),
                           "observedTurns": sum(len(receipt["turns"]) for receipt in recorded),
                           "primary": calculated, "reviews": semantic[model],
                           "contextAnswerLeakage": context_answers_in_history(recorded, jobs)}
    return {"archiveSHA256": file_hash(archive), "corpusHash": corpus.digest(cases),
            "integrity": "recorded checks and primary metrics reproduced",
            "meaning": "Integrity is not semantic correctness, statistical confidence or release readiness.",
            "models": findings}


def context_answers_in_history(results: list[dict], jobs: dict[str, dict]) -> list[dict]:
    matches = []
    for case in results:
        if case["group"] != "context":
            continue
        for index, turn in enumerate(case["turns"]):
            requests = turn.get("requests", [])
            if not requests:
                continue
            messages = "\n".join(message["content"] for message in requests[-1]["messages"]).casefold()
            rules = jobs[case["job"]]["case"]["turns"][index].get("checks", [])
            values = {value for rule in rules if rule["kind"] in {"reply_equals", "contains_any"}
                      for value in rule["values"] if value.casefold() in messages}
            if values:
                matches.append({"job": case["job"], "turn": index, "answerAnchors": sorted(values)})
    return matches
