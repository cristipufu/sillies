#!/usr/bin/env python3
"""Reuse agent judgments only when a rerun preserves the evaluated task evidence."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "Benchmarks/Chat"))
from evaluation import receipts, reviews as review_validation  # noqa: E402
from evaluation.storage import write_json  # noqa: E402

EVIDENCE_FIELDS = (
    "input", "reply", "error", "partialReply", "summary", "sources", "memories",
    "compacted", "compactionCalls", "checks", "rubric",
)


def decoded(value):
    if not isinstance(value, str):
        return value
    try:
        return json.loads(value)
    except ValueError:
        return value


def conversation_passages(value):
    if isinstance(value, list):
        return [conversation_passages(item) for item in value]
    if isinstance(value, dict):
        # Synthetic conversations receive new message UUIDs on every run. Keep
        # quoted text, speaker and date; never remove saved Vault record IDs.
        return {key: conversation_passages(item) for key, item in value.items() if key != "messageID"}
    return value


def task_evidence(turn):
    evidence = {key: turn.get(key) for key in EVIDENCE_FIELDS}
    calls = []
    for call in turn.get("calls", []):
        result = decoded(call.get("result"))
        if call["name"] == "search_conversation":
            result = conversation_passages(result)
        calls.append({"name": call["name"], "arguments": decoded(call["arguments"]),
                      "result": result, "error": call.get("error")})
    return evidence | {"calls": calls}


def read(path):
    return json.loads(path.read_text())


def recheck(source: Path, destination: Path, model: str) -> int:
    old_configuration, configuration = read(source / "run.json"), read(destination / "run.json")
    if old_configuration["corpusHash"] != configuration["corpusHash"]:
        raise ValueError("Review equivalence requires the same frozen corpus and rubrics")
    old_results, current_results = receipts.load(source, old_configuration), receipts.load(destination, configuration)
    old_reviews = read(source / "reviews.json")
    review_validation.summarize(old_reviews, old_results)
    original = {(item["job"], item["turn"]): item for item in old_reviews
                if item["model"] == model and item.get("scope") == "rubric"}
    path = destination / "reviews.json"
    reviews = read(path) if path.exists() else []
    review_validation.summarize(reviews, current_results)
    existing = {(item["model"], item["job"], item["turn"]) for item in reviews}
    previous = {case["job"]: case for case in old_results[model]}
    added = 0
    for current in current_results[model]:
        old = previous.get(current["job"])
        if old is None:
            continue
        for index, turn in enumerate(current["turns"]):
            review = original.get((current["job"], index))
            if review is None or (model, current["job"], index) in existing:
                continue
            old_turn = old["turns"][index]
            if task_evidence(old_turn) != task_evidence(turn):
                continue
            reviews.append(review | {
                "responseHash": turn["responseHash"], "evidenceHash": turn["evidenceHash"],
                "equivalentEvidenceHash": review["evidenceHash"],
                "note": review["note"] + " Rechecked equivalent task evidence; excludes elapsed timing and generated conversation message IDs, preserving source text, roles, dates and Vault IDs.",
            })
            added += 1
    write_json(path, reviews)
    return added


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("model")
    options = parser.parse_args()
    print(f"Rechecked {recheck(options.source, options.destination, options.model)} equivalent turns")


if __name__ == "__main__":
    main()
