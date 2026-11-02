"""Explicit reviewer judgments stay separate from checks and bind to the entire observed task."""
from __future__ import annotations

import json
from pathlib import Path

from . import evidence


def load(output: Path, results: dict[str, list[dict]]) -> dict[str, dict]:
    path = output / "reviews.json"
    entries = json.loads(path.read_text()) if path.exists() else []
    return summarize(entries, results)


def summarize(entries: list[dict], results: dict[str, list[dict]]) -> dict[str, dict]:
    known = {(model, result["job"], index): turn
             for model, cases in results.items() for result in cases
             for index, turn in enumerate(result["turns"])}
    judgments = {}
    for review in entries:
        key = review["model"], review["job"], review["turn"]
        if key in judgments or key not in known:
            raise ValueError(f"Duplicate or unknown semantic review: {key}")
        validate(review, known[key])
        judgments[key] = review
    return {model: model_summary(model, cases, judgments) for model, cases in results.items()}


def validate(review: dict, turn: dict) -> None:
    if review["responseHash"] != evidence.response_hash(turn):
        raise ValueError("Semantic review refers to an outdated response")
    if "evidenceHash" in review:
        if review["evidenceHash"] != evidence.review_hash(turn):
            raise ValueError("Semantic review refers to outdated task evidence")
        if not review.get("reviewer", "").strip() or not review.get("scope", "").strip():
            raise ValueError("An evidence-bound review needs a reviewer and scope")
    elif review.get("scope") == "rubric":
        raise ValueError("A full rubric review must bind to task evidence")
    if review["verdict"] not in {"pass", "fail", "uncertain"} or not review.get("note", "").strip():
        raise ValueError("A semantic review needs a verdict and rationale")


def full_rubric(review: dict) -> bool:
    return review.get("scope") == "rubric" and "evidenceHash" in review


def rubric_status(verdicts: list[dict]) -> str:
    bound = [review for review in verdicts if full_rubric(review)]
    if any(review["verdict"] == "fail" for review in bound):
        return "fail"
    if len(bound) == len(verdicts) and all(review["verdict"] == "pass" for review in bound):
        return "pass"
    return "pending"


def model_summary(model: str, cases: list[dict], judgments: dict) -> dict:
    primary = [case for case in cases if case["profile"] == "app"]
    primary_ids = {case["job"] for case in primary}
    model_reviews = [review for (owner, _, _), review in judgments.items() if owner == model]
    primary_reviews = [review for review in model_reviews if review["job"] in primary_ids]
    counts = {verdict: sum(review["verdict"] == verdict for review in model_reviews)
              for verdict in ("pass", "fail", "uncertain")}
    counts.update(primaryTurns=sum(len(case["turns"]) for case in primary),
                  primaryReviewedTurns=len(primary_reviews),
                  primaryRubricReviewedTurns=sum(full_rubric(review) for review in primary_reviews),
                  legacyReplyOnlyReviews=sum("evidenceHash" not in review for review in primary_reviews),
                  rubricCases={"pass": 0, "fail": 0, "pending": 0})
    for case in primary:
        verdicts = [judgments.get((model, case["job"], index), {}) for index in range(len(case["turns"]))]
        counts["rubricCases"][rubric_status(verdicts)] += 1
    return counts
