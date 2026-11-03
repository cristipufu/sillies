"""Reproduce diagnostic measurements from audited, fully reviewed experiment archives."""
from __future__ import annotations

import argparse
import importlib.util
import json
from collections import defaultdict
from pathlib import Path


def load_measurement_module(repository: Path):
    path = repository / "scripts/summarize-chat-benchmarks.py"
    specification = importlib.util.spec_from_file_location("chat_measurements", path)
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


def native_metrics(generation):
    return (generation.get("output", {}).get("metrics")
            or generation.get("failure", {}).get("metrics"))


def normalized_request(request):
    return {key: value for key, value in request.items()
            if key not in {"conversationID", "sessionID"}}


def native_stages(cases):
    stages = defaultdict(lambda: defaultdict(float))
    missing = 0
    for case in cases:
        for turn in case["turns"]:
            for generation in turn.get("generations", []):
                metrics = native_metrics(generation)
                if metrics is None:
                    missing += 1
                    continue
                stage = stages[generation["request"]["style"]]
                stage["count"] += 1
                for key in ("promptSeconds", "generationSeconds", "processedPromptTokens", "generatedTokens"):
                    stage[key] += metrics[key]
    return {"styles": dict(stages), "generationsWithoutMetrics": missing}


def exact_answer_checks(cases):
    checks = [check for case in cases for turn in case["turns"]
              for check in turn["checks"] if check["kind"] == "reply_equals"]
    return {"passed": sum(check["passed"] for check in checks), "total": len(checks)}


def per_repeat(cases, judgments, measurements):
    result = {}
    for repeat in sorted({case["repeat"] for case in cases}):
        selected = [case for case in cases if case["repeat"] == repeat]
        result[str(repeat)] = {
            "reviewedPasses": sum(measurements.reviewed_case(case, judgments) for case in selected),
            "cases": len(selected),
            "automatic": measurements.report.aggregate(selected),
        }
    return result


def measure_run(path, measurements):
    document = measurements.audit.read_document(path)
    configuration, results = measurements.complete_run(path)
    judgments = measurements.review_index(path, results)
    models = measurements.primary_measurements(results, judgments)
    for model, cases in results.items():
        models[model]["nativeStages"] = native_stages(cases)
        peaks = [(native_metrics(generation) or {}).get("peakDeviceMemoryBytes")
                 for case in cases for turn in case["turns"]
                 for generation in turn.get("generations", [])]
        models[model]["peakDeviceMemoryBytes"] = max((value for value in peaks if value is not None), default=None)
        models[model]["exactAnswerChecks"] = exact_answer_checks(cases)
        models[model]["repeats"] = per_repeat(cases, judgments, measurements)
        models[model]["caseOutcomes"] = {
            case["job"]: measurements.reviewed_case(case, judgments) for case in cases}
    return {"corpusHash": configuration["corpusHash"], "models": models}, document


def paired_first_prompts(baseline, candidate, percentile):
    models = {}
    for model, recorded in baseline["models"].items():
        if model not in candidate["models"]:
            continue
        candidates = {case["job"]: case for case in candidate["models"][model]["cases"]}
        pairs = []
        for case in recorded["cases"]:
            other = candidates.get(case["job"])
            if other is None:
                continue
            first = case["turns"][0].get("generations", [])
            second = other["turns"][0].get("generations", [])
            if not first or not second:
                continue
            left, right = first[0], second[0]
            if normalized_request(left["request"]) != normalized_request(right["request"]):
                continue
            before, after = native_metrics(left), native_metrics(right)
            if not before or not after:
                continue
            pairs.append({"job": case["job"], "style": left["request"]["style"],
                          "baseline": before, "candidate": after})
        ratios = [pair["baseline"]["promptSeconds"] / pair["candidate"]["promptSeconds"]
                  for pair in pairs if pair["candidate"]["promptSeconds"] > 0]
        models[model] = {"pairs": pairs, "promptSpeedupP50": percentile(ratios, .5)}
    return models


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", type=Path, default=Path.cwd())
    parser.add_argument("--archives", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    options = parser.parse_args()
    measurements = load_measurement_module(options.repository.resolve())
    runs, documents = {}, {}
    for path in sorted(options.archives.glob("*.json.gz")):
        if path.name in {"controls.json.gz", "apple-measured-control.json.gz", "pilot.json.gz"}:
            continue
        name = path.name.removesuffix(".json.gz")
        runs[name], documents[name] = measure_run(path, measurements)
    comparisons = {}
    for name in ("candidate-final",):
        if name in documents:
            comparisons[name] = paired_first_prompts(
                documents["baseline"], documents[name], measurements.report.percentile)
    result = {"runs": runs, "pairedFirstPrompts": comparisons,
              "percentiles": "Repository nearest-observation convention; completed turns only for timing.",
              "limitations": "Main comparison: two exposed-regression repeats. Capacity and boundary controls: one pass per configuration. One machine; implementing-agent rubric review, not blinded or independent."}
    options.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
