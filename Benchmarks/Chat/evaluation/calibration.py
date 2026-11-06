"""Qualify a prefill change only from matching, completed and fully reviewed app-workflow runs."""
from __future__ import annotations

import json
import math
from pathlib import Path

from . import corpus, receipts, report, reviews

MINIMUM_CASES = 6
MINIMUM_REPEATS = 2
REQUIRED_SPEED_RATIO = 0.9
MATCHED_FIELDS = ("corpusHash", "catalogHash", "workerHash", "helperHash", "runtimeResources",
                  "evaluatorHash", "machine", "models", "jobs", "repeats", "orderSeed",
                  "turnTimeout", "caseTimeout", "startupTimeout")


def load_run(directory: Path, model: str) -> dict:
    summary = report.generate(directory)
    config = summary["configuration"]
    if model == "apple" or model not in config["models"]:
        raise ValueError("Calibration requires the same downloaded model in both runs")
    if config["repeats"] < MINIMUM_REPEATS or len(config["cases"]) < MINIMUM_CASES:
        raise ValueError("Use at least six distinct app scenarios and two repeats")
    result = summary["models"][model]
    if result["pendingPrimaryCases"] or result["primary"]["cases"] == 0:
        raise ValueError("Pending cases cannot qualify a runtime change")
    judgments = json.loads((directory / "reviews.json").read_text())
    judged = {(item["job"], item["turn"]): item for item in judgments if item["model"] == model}
    primary = [case for case in receipts.load(directory, config)[model] if case["profile"] == "app"]
    if len({case["case"] for case in primary}) < MINIMUM_CASES:
        raise ValueError("Ablations do not count toward the six required app scenarios")
    if not {"identity", "memories", "vault", "mixed-knowledge"} <= {case["group"] for case in primary}:
        raise ValueError("Qualification must cover identity, memories, Vault and mixed knowledge")
    for case in primary:
        for index, turn in enumerate(case["turns"]):
            review = judged.get((case["job"], index), {})
            if not reviews.full_rubric(review) or review["verdict"] == "uncertain":
                raise ValueError("Every turn needs an evidence-bound, decisive full-rubric review")
    metadata = json.loads((directory / model / "model.json").read_text())
    return {"configuration": config, "result": result, "cases": primary,
            "reviews": judged, "metadata": metadata}


def qualify(baseline: Path, candidate: Path, model: str) -> dict:
    return compare(load_run(baseline, model), load_run(candidate, model))


def compare(baseline: dict, candidate: dict) -> dict:
    before, after = baseline["configuration"], candidate["configuration"]
    if any(before[field] != after[field] for field in MATCHED_FIELDS):
        raise ValueError("Comparison conditions differ; rerun with identical frozen evidence")
    if before.get("prefillChunkTokens") is not None or not after.get("prefillChunkTokens"):
        raise ValueError("Compare catalog defaults against an explicit candidate chunk size")
    identity = baseline["metadata"].get("calibrationIdentity")
    if not identity or identity != candidate["metadata"].get("calibrationIdentity"):
        raise ValueError("Missing or mismatched runtime identity")
    if baseline["metadata"]["profile"] != identity["profile"]:
        raise ValueError("The control must use its original catalog profile")
    changed = candidate["metadata"]["profile"]
    expected = dict(identity["profile"], prefill={"chunkTokens": after["prefillChunkTokens"]})
    if changed != expected:
        raise ValueError("Only prefill batching may differ")
    new_failures = regressions(baseline, candidate)
    first = baseline["result"]["primary"]["firstTextP50"]
    second = candidate["result"]["primary"]["firstTextP50"]
    if new_failures or not first or not second or not math.isfinite(first) or not math.isfinite(second) or second <= 0 or second > first * REQUIRED_SPEED_RATIO:
        raise ValueError("No qualification: new failure or less than 10% median first-text improvement")
    turns = candidate["result"]["primary"]["turns"]
    return {"version": 1, "identity": identity, "chunkTokens": after["prefillChunkTokens"],
            "evidence": {"baselineHash": run_digest(baseline), "candidateHash": run_digest(candidate),
                         "corpusHash": after["corpusHash"], "comparedCases": len(after["cases"]),
                         "repeats": after["repeats"], "reviewedTurns": turns, "totalTurns": turns,
                         "newFailures": 0, "baselineFirstTextMedian": first,
                         "candidateFirstTextMedian": second}}


def run_digest(run: dict) -> str:
    return corpus.digest(dict(run, reviews=[run["reviews"][key] for key in sorted(run["reviews"])]))


def regressions(baseline: dict, candidate: dict) -> int:
    old = {case["job"]: case for case in baseline["cases"]}
    new = {case["job"]: case for case in candidate["cases"]}
    if old.keys() != new.keys():
        raise ValueError("Different completed case coverage")
    failures = 0
    for job, previous in old.items():
        for index, (before, after) in enumerate(zip(previous["turns"], new[job]["turns"], strict=True)):
            if after.get("error") or not after.get("reply"):
                failures += 1
            # A fixed expectation stays a fixed expectation; improvements cannot cancel new misses.
            if any(a["passed"] and not b["passed"] for a, b in zip(before["checks"], after["checks"], strict=True)):
                failures += 1
            if baseline["reviews"][(job, index)]["verdict"] == "pass" and candidate["reviews"][(job, index)]["verdict"] != "pass":
                failures += 1
    return failures
