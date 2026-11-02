#!/usr/bin/env python3
"""Derive comparison measurements from complete, validated Chat benchmark receipts."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "Benchmarks/Chat"))
from evaluation import audit, receipts, report, reviews  # noqa: E402
from evaluation.storage import write_json  # noqa: E402


def read(path: Path):
    return json.loads(path.read_text())


def complete_run(source: Path):
    if source.is_dir():
        configuration = read(source / "run.json")
        results = receipts.load(source, configuration)
    else:
        audit.verify(source)
        document = audit.read_document(source)
        configuration = document["configuration"]
        results = {model: value["cases"] for model, value in document["models"].items()}
    planned = len(configuration["jobs"])
    if any(len(cases) != planned for cases in results.values()):
        raise ValueError("Complete every planned case before publishing a comparison")
    return configuration, results


def review_index(source: Path, results):
    entries = (read(source / "reviews.json") if source.is_dir()
               else audit.read_document(source).get("reviews", []))
    reviews.summarize(entries, results)  # Reject stale, duplicate or unknown judgments.
    return {(item["model"], item["job"], item["turn"]): item for item in entries}


def model_metadata(source: Path, models):
    if source.is_dir():
        return {model: read(source / model / "model.json") for model in models}
    document = audit.read_document(source)
    return {model: document["models"][model]["metadata"] for model in models}


def matched_model_metadata(primary, repeated):
    if not primary or any(not metadata for metadata in primary.values()) or primary != repeated:
        raise ValueError("Repeated measurements need matching recorded model revisions and runtime metadata")


def reviewed_case(case, judgments):
    decisions = [judgments.get((case["model"], case["job"], index), {})
                 for index in range(len(case["turns"]))]
    if any(not reviews.full_rubric(item) for item in decisions):
        raise ValueError(f"Every primary turn needs a full-rubric review: {case['job']}")
    # One demonstrated failure settles the task without pretending an uncertain follow-up passed.
    if any(item["verdict"] == "fail" for item in decisions):
        return False
    if any(item["verdict"] == "uncertain" for item in decisions):
        raise ValueError(f"The primary task outcome is still uncertain: {case['job']}")
    completed = not case.get("error") and not any(turn.get("error") for turn in case["turns"])
    return completed and all(item["verdict"] == "pass" for item in decisions)


def correct_short_answer_times(cases, judgments):
    """First answer-bearing text only where the entire answer meets an exact-answer rubric."""
    times = []
    for case in cases:
        for index, turn in enumerate(case["turns"]):
            judgment = judgments[(case["model"], case["job"], index)]
            exact = [check for check in turn["checks"] if check["kind"] == "reply_equals"]
            if turn.get("error") or judgment["verdict"] != "pass" or not exact or not all(c["passed"] for c in exact):
                continue
            first = next((event["seconds"] for event in turn.get("textEmissions", [])
                          if any(character.isalnum() for character in event["text"])), None)
            if first is not None:
                times.append(first)
    return {"count": len(times), "p50": report.percentile(times, .5), "p95": report.percentile(times, .95)}


def memory_write_attempts(cases):
    """Count executed save calls on no-write turns, including failed tool executions."""
    protected, violated = 0, 0
    for case in cases:
        for turn in case["turns"]:
            if any(check["kind"] == "no_writes" for check in turn["checks"]):
                protected += 1
                violated += any(call["name"] == "save_memory" for call in turn["calls"])
    return {"noWriteTurns": protected, "turnsWithUnwantedSaveCall": violated}


def timing_counts(cases):
    turns = [turn for case in cases for turn in case["turns"] if not turn.get("error")]
    return {"firstTextTurns": sum(turn.get("firstTextSeconds") is not None for turn in turns),
            "completedTimedTurns": sum(turn.get("seconds") is not None for turn in turns)}


def memory_state_changes(cases, judgments):
    required, passed = 0, 0
    for case in cases:
        for index, turn in enumerate(case["turns"]):
            kinds = {check["kind"] for check in turn["checks"]}
            # Later recall turns may require an existing value but explicitly forbid a new write.
            if "memory_contains" not in kinds or "no_writes" in kinds:
                continue
            required += 1
            state = [check for check in turn["checks"] if check["kind"] in {"memory_contains", "memory_absent"}]
            verdict = judgments[(case["model"], case["job"], index)]["verdict"]
            passed += not turn.get("error") and verdict == "pass" and all(check["passed"] for check in state)
    return {"requiredTurns": required, "reviewedPasses": passed}


def tool_scaling_measurements(cases):
    scaling = [case for case in cases if case["group"] == "tool-scaling"]
    return {profile: report.aggregate([case for case in scaling if case["profile"] == profile])
            for profile in sorted({case["profile"] for case in scaling})}


def primary_measurements(results, judgments):
    models = {}
    for model, all_cases in results.items():
        cases = [case for case in all_cases if case["profile"] == "app"]
        decisions = {case["job"]: reviewed_case(case, judgments) for case in cases}
        groups = {}
        for group in sorted({case["group"] for case in cases}):
            subset = [case for case in cases if case["group"] == group]
            groups[group] = {"passed": sum(decisions[case["job"]] for case in subset), "total": len(subset)}
        compaction = [{"case": case["case"], "turn": index, "calls": turn.get("compactionCalls"),
                       "seconds": turn.get("compactionSeconds"), "reply": turn.get("reply"), "error": turn.get("error")}
                      for case in cases if case["group"] == "context"
                      for index, turn in enumerate(case["turns"])]
        models[model] = {
            "reviewedPasses": sum(decisions.values()), "cases": len(cases),
            "score": 100 * sum(decisions.values()) / len(cases),
            "automatic": report.aggregate(cases), "timingSampleCounts": timing_counts(cases), "groups": groups,
            "toolScaling": tool_scaling_measurements(all_cases),
            "correctShortAnswerFirstText": correct_short_answer_times(cases, judgments),
            "memoryWriteAttempts": memory_write_attempts(cases),
            "memoryStateChanges": memory_state_changes(cases, judgments), "compaction": compaction,
        }
    return models


def matched_extension(primary, repeated):
    comparable = ("sourceCommit", "evaluatorHash", "workerHash", "helperHash", "catalogHash",
                  "runtimeResources", "machine", "turnTimeout", "caseTimeout", "startupTimeout")
    if any(primary[key] != repeated[key] for key in comparable):
        raise ValueError("Repeated measurements must use the same build, runtime and machine")
    if primary.get("modelReleases") != repeated.get("modelReleases"):
        raise ValueError("Repeated measurements must preserve the frozen model release metadata")
    if set(primary["models"]) != set(repeated["models"]):
        raise ValueError("Repeated measurements must cover the same models")
    originals = {case["id"]: case for case in primary["cases"]}
    if any(originals.get(case["id"]) != case for case in repeated["cases"]):
        raise ValueError("Repeated scenarios must match their original frozen fixtures exactly")


def comparison_passes(primary, repeated):
    subset = [case for case in repeated if case["profile"] == "app"]
    identifiers = {case["case"] for case in subset}
    baseline = [case for case in primary if case["profile"] == "app" and case["case"] in identifiers]
    rounds = [baseline] + [[case for case in subset if case["repeat"] == number]
                           for number in sorted({case["repeat"] for case in subset})]
    if any({case["case"] for case in items} != identifiers for items in rounds):
        raise ValueError("Each repeated pass must contain every comparison scenario")
    return identifiers, rounds


def repeat_timings(primary, repeated):
    measurements = {}
    for model, cases in repeated.items():
        _, rounds = comparison_passes(primary[model], cases)
        measurements[model] = [{"automatic": report.aggregate(items), "sampleCounts": timing_counts(items)}
                               for items in rounds]
    return measurements


def repeat_measurements(primary, repeated):
    measurements = {}
    for model, cases in repeated.items():
        identifiers, rounds = comparison_passes(primary[model], cases)
        by_case = {identifier: [next(case["passed"] for case in items if case["case"] == identifier)
                                for items in rounds] for identifier in sorted(identifiers)}
        measurements[model] = {
            "casesPerPass": len(identifiers),
            "automatedPasses": [sum(case["passed"] for case in items) for items in rounds],
            "errorTurns": [sum(bool(turn.get("error")) for case in items for turn in case["turns"])
                           for items in rounds],
            "allPassesSucceeded": sum(all(outcomes) for outcomes in by_case.values()),
            "changedOutcome": sum(len(set(outcomes)) > 1 for outcomes in by_case.values()),
            "outcomes": by_case,
        }
    return measurements


def summarize(primary_source: Path, repeated_source: Path | None = None):
    configuration, primary = complete_run(primary_source)
    metadata = model_metadata(primary_source, configuration["models"])
    judgments = review_index(primary_source, primary)
    result = {"sourceCommit": configuration["sourceCommit"], "machine": configuration["machine"], "models": metadata,
              "primaryCorpusHash": configuration["corpusHash"]}
    if repeated_source is not None:
        repeat_configuration, repeated = complete_run(repeated_source)
        matched_extension(configuration, repeat_configuration)
        matched_model_metadata(metadata, model_metadata(repeated_source, repeat_configuration["models"]))
        result["repeatCorpusHash"] = repeat_configuration["corpusHash"]
    result["primary"] = primary_measurements(primary, judgments)
    if repeated_source is not None:
        result["repeatedAutomaticChecks"] = repeat_measurements(primary, repeated)
    if "modelReleases" in configuration:
        # Keep release metadata absent when reproducing older archives that did not record it.
        result["modelReleases"] = configuration["modelReleases"]
        if repeated_source is not None:
            result["repeatedTiming"] = repeat_timings(primary, repeated)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("primary", type=Path, help="Complete run directory or published .json.gz archive")
    parser.add_argument("repeated", type=Path, nargs="?", help="Optional complete matched repeat run or archive")
    parser.add_argument("--output", type=Path, required=True)
    options = parser.parse_args()
    write_json(options.output, summarize(options.primary, options.repeated))


if __name__ == "__main__":
    main()
