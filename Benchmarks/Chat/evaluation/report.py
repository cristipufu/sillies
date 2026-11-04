"""Keep coverage, behavior, exact answers and lexical anchors distinct in comparisons."""
from __future__ import annotations

import json
from pathlib import Path

from .corpus import PROFILES
from . import receipts, reviews
from .storage import write_json


def percentile(values: list[float], fraction: float) -> float | None:
    if not values:
        return None
    values = sorted(values)
    return values[round((len(values) - 1) * fraction)]


def aggregate(results: list[dict]) -> dict:
    turns = [turn for result in results for turn in result["turns"]]
    categories = {}
    for category in ("behavior", "exact_answer", "lexical_anchor"):
        checks = [check for turn in turns for check in turn["checks"] if check["category"] == category]
        categories[category] = {"passed": sum(bool(check["passed"]) for check in checks), "total": len(checks)}
    latency = [turn["seconds"] for turn in turns if not turn.get("error") and "seconds" in turn]
    first = [turn["firstTextSeconds"] for turn in turns if not turn.get("error") and turn.get("firstTextSeconds") is not None]
    return {"cases": len(results), "passed": sum(result["passed"] for result in results),
            "turns": len(turns), "errors": sum(bool(turn.get("error")) for turn in turns),
            "checks": categories, "firstTextP50": percentile(first, .5), "firstTextP95": percentile(first, .95),
            "totalP50": percentile(latency, .5), "totalP95": percentile(latency, .95)}


def ratio(value: dict) -> str:
    return f"{value['passed']}/{value['total']}" if value["total"] else "—"


def seconds(value: float | None) -> str:
    return f"{value:.2f}s" if value is not None else "—"


def generate(output: Path) -> dict:
    configuration = json.loads((output / "run.json").read_text())
    all_results = receipts.load(output, configuration)
    semantic_reviews = reviews.load(output, all_results)
    rows, summary = [], {"configuration": configuration, "models": {}}
    for model in configuration["models"]:
        results = all_results[model]
        primary = [result for result in results if result["profile"] == "app"]
        release = configuration.get("modelReleases", {}).get(model)
        release_date = release["date"] if release else ("System-managed" if model == "apple" else "Not recorded")
        stats = aggregate(primary)
        total = sum(job["profile"] == "app" for job in configuration["jobs"])
        review = semantic_reviews[model]
        groups = {group: aggregate([result for result in primary if result["group"] == group])
                  for group in sorted({result["group"] for result in primary})}
        profiles = {profile: aggregate([result for result in results if result["profile"] == profile])
                    for profile in PROFILES if any(result["profile"] == profile for result in results)}
        summary["models"][model] = {"completed": len(results), "planned": len(configuration["jobs"]),
                                    "release": release, "primary": stats, "groups": groups, "profiles": profiles,
                                    "semanticReviews": review,
                                    "pendingPrimaryCases": total - len(primary),
                                    "evidenceValidation": "recomputed" if configuration.get("cases") else "legacy-inventory-and-reply-hashes"}
        rows.append(f"| {model} | {release_date} | {len(primary)}/{total} | {stats['passed']}/{total} | "
                    f"{ratio(stats['checks']['behavior'])} | {ratio(stats['checks']['exact_answer'])} | "
                    f"{ratio(stats['checks']['lexical_anchor'])} | {review['primaryRubricReviewedTurns']}/{stats['turns']} | {seconds(stats['firstTextP50'])} / {seconds(stats['firstTextP95'])} | "
                    f"{seconds(stats['totalP50'])} | {stats['errors']} |")
    lines = ["# Local Chat model evaluation", "", "Primary comparison: the app's production tools, recorded in each delivered request. Automated checks alone do not establish answer correctness or release readiness.", "",
             "| Model | Model release | Completed/planned | Checks passed/planned | Behavior checks | Exact answers | Lexical anchors | Full rubric reviews/observed turns | First text p50 / p95 | Turn p50 | Failed turns |",
             "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |", *rows, "",
             "Model release means the original publisher release, not a converted checkpoint upload; source links are frozen in run.json.",
             "Missing cases remain pending in the planned denominator. Failed and timed-out cases remain failures; pending is not a measured failure.",
             "Open-ended answers need full rubric review bound to the input, tool calls, saved state and reply. Unreviewed turns remain pending.",
             "Earlier reply-only/content-only reviews remain separately visible in summary.json; they do not certify the full task rubric.",
             "Exact answers combine answer content and requested formatting. A correct full sentence can fail a name-only instruction.",
             "Lexical anchors are weak checks, not factual-accuracy scores. Review raw replies against their rubrics before recommending a model.",
             "Hash-validated semantic reviews, when provided, are counted separately in summary.json; unreviewed responses are not implicitly correct.",
             "Latency includes the production conversation service and instrumentation. Initial worker turns may include model loading; Apple assets may already be warm.",
             "Unequal or incomplete coverage is not a fair final ranking. Tool-count curves and group breakdowns are in summary.json.", ""]
    (output / "report.md").write_text("\n".join(lines))
    write_json(output / "summary.json", summary)
    return summary
