"""Reproduce the bounded study's measurements without inference, downloads or app data."""
from __future__ import annotations

import copy
import gzip
import hashlib
import json
import math
from pathlib import Path
import statistics
import sys
import tempfile


DIRECTORY = Path(__file__).resolve().parent


def read_json(path: Path) -> dict:
    return json.loads(path.read_text())


def read_compressed(name: str) -> dict:
    return json.loads(gzip.decompress((DIRECTORY / name).read_bytes()))


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def materialize(archive: dict, destination: Path) -> None:
    for name, artifact in archive["artifacts"].items():
        relative = Path(name)
        require(not relative.is_absolute() and ".." not in relative.parts, "Unsafe artifact path")
        payload = artifact["text"].encode()
        require(hashlib.sha256(payload).hexdigest() == artifact["sha256"], f"Altered artifact: {name}")
        path = destination / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(payload)


def chat_statistics(root: Path, receipts) -> dict:
    statistics_by_run = {}
    for run in sorted(root.glob("*/run.json")):
        configuration = read_json(run)
        models = receipts.load(run.parent, configuration)
        records = [record for cases in models.values() for record in cases]
        require(len(records) == len(configuration["jobs"]) * len(models), f"Missing cases: {run.parent.name}")
        turns = [turn for record in records for turn in record["turns"]]
        first_text = [turn["firstTextSeconds"] for turn in turns if turn.get("firstTextSeconds") is not None]
        statistics_by_run[run.parent.name] = {
            "cases": len(records),
            "passed": sum(record["passed"] for record in records),
            "turns": len(turns),
            "failedTurns": sum(bool(turn.get("error")) for turn in turns),
            "attemptedTurnMedianSeconds": statistics.median(turn["seconds"] for turn in turns if "seconds" in turn),
            "firstTextMedianSeconds": statistics.median(first_text) if first_text else None,
            "terminalCompositionRounds": sum(
                "App record of completed tool work" in str(generation["request"])
                for turn in turns for generation in turn.get("generations", [])
            ),
        }
    return statistics_by_run


def validate_voice(report: dict, model: str) -> list[dict]:
    require(report["voiceModel"] == model, "Unexpected voice model")
    expected = 3 if "order" in report else 5
    require(len(report["observations"]) == expected, "Incomplete voice comparison")
    observations = report["observations"][1:]
    for observation in observations:
        spoken = " ".join(observation["spokenPhrases"]).split()
        require(observation["text"].split() == spoken, "Missing or duplicated spoken words")
        times = [chunk["arrived"] for chunk in observation["audio"]["chunks"]]
        require(bool(times) and times == sorted(times), "Missing or reordered PCM")
        require(all(math.isfinite(time) and time >= 0 for time in times), "Invalid PCM timing")
    return observations


def voice_statistics(root: Path) -> dict:
    selected = read_json(root / "voice-pairs-registration.json")["selectedControls"]
    statistics_by_model = {}
    for model, runs in selected.items():
        reports = [read_json(root / run / "spoken-answer.json") for run in runs]
        observations = [value for report in reports for value in validate_voice(report, model)]
        row = {
            "textModel": reports[0]["textModel"], "runs": runs, "observations": len(observations),
            "sameTextAcrossAll": len({value["text"] for value in observations}) == 1,
            "allWordsDelivered": True,
        }
        require(row["sameTextAcrossAll"], "The paired text changed")
        for arm in ("current", "early"):
            values = [value for value in observations if value["opening"] == arm]
            require(len(values) == 2, "Unbalanced comparison")
            metrics = {
                "firstText": [value["firstTextSeconds"] for value in values],
                "synthesisRequested": [value["synthesisRequestedSeconds"] for value in values],
                "firstPCM": [value["audio"]["chunks"][0]["arrived"] for value in values],
                "firstNonSilentPCM": [value["audio"]["firstNonSilentPCM"] for value in values],
                "simulatedGap": [value["audio"]["simulatedPlaybackGapSeconds"] for value in values],
                "textCompleted": [value["textSeconds"] for value in values],
                "spokenWords": [len(value["text"].split()) for value in values],
            }
            row[arm] = {"count": len(values)}
            for metric, samples in metrics.items():
                require(all(math.isfinite(value) and value >= 0 for value in samples), f"Invalid {metric}")
                row[arm][metric] = statistics.median(samples)
        statistics_by_model[model] = row
    return statistics_by_model


def endpoint_statistics(root: Path) -> dict:
    rows = read_json(root / "endpoint-results.json")["rows"]
    selection = read_json(root / "endpoint-selection.json")
    require({row["row"] for row in rows} == {row["row_idx"] for row in selection}, "Changed endpoint sample")
    require(len({row["row"] for row in rows}) == len(rows), "Duplicated endpoint row")
    sources = {row["row_idx"]: row["row"] for row in selection}
    for row in rows:
        source = sources[row["row"]]
        require(row["id"] == source["id"] and row["language"] == source["language"], "Wrong endpoint identity")
        require(row["complete"] == source["endpoint_bool"], "Changed endpoint label")
        require(math.isfinite(row["probability"]) and 0 <= row["probability"] <= 1, "Invalid endpoint probability")
    complete = [row for row in rows if row["complete"]]
    incomplete = [row for row in rows if not row["complete"]]
    return {
        "total": len(rows), "complete": len(complete), "incomplete": len(incomplete),
        "medianSeconds": statistics.median(row["seconds"] for row in rows),
        "thresholds": {
            str(threshold): {
                "acceptedComplete": sum(row["probability"] >= threshold for row in complete),
                "premature": sum(row["probability"] >= threshold for row in incomplete),
            }
            for threshold in read_json(root / "endpoint-registration.json")["thresholdCandidates"]
        },
    }


def budget_statistics(root: Path) -> dict:
    ledger = read_json(root / "execution-ledger.json")
    for run in ledger["runs"]:
        require(run["status"] != "running", "Unfinished execution")
        require(0 <= run["elapsedSeconds"] <= run["reservedSeconds"], "Execution exceeded its reserved deadline")
        require(hashlib.sha256((root / run["log"]).read_bytes()).hexdigest() == run["logSHA256"], "Altered execution log")
    executed = sum(run["elapsedSeconds"] for run in ledger["runs"])
    require(executed <= ledger["limitSeconds"], "Native budget exceeded")
    return {"limitSeconds": ledger["limitSeconds"], "executedSeconds": executed, "runs": len(ledger["runs"])}


def validate_reviews(root: Path, reviews: dict) -> None:
    require(reviews["reviewer"] == "implementing-agent", "Unrecorded independent review")
    seen = set()
    for review in reviews["turns"]:
        identity = (review["record"], review["turn"])
        require(identity not in seen, "Duplicated review")
        seen.add(identity)
        turn = read_json(root / review["record"])["turns"][review["turn"]]
        require(turn["evidenceHash"] == review["evidenceHash"], "Review belongs to different evidence")
        require(turn["responseHash"] == review["responseHash"], "Review belongs to another answer")
        require(review["assessment"] and review["scope"], "Missing review rationale")
    continuation = [review for review in reviews["turns"] if review["scope"] == "heard-step-continuation"]
    for arm, expected in (("baseline", 0), ("candidate-final", 1)):
        matching = [review for review in continuation if review["arm"] == arm]
        require(len(matching) == 6, "Missing continuation review")
        require(sum(review["passesContinuity"] for review in matching) == expected, "Review totals differ from report")


def validate_application_receipts(root: Path) -> None:
    validation = read_json(root / "validation-receipts.json")
    expected = {"make-check-retained": 763, "make-stress": 183, "make-race-check": 221, "race-playback-final": 14}
    for command, count in expected.items():
        result = validation[command]
        receipts = [
            receipt for directory in result["receiptDirectories"]
            for receipt in read_json(root / directory / "verified.json")
        ]
        require(sum(receipt["tests"] for receipt in receipts) == count == result["tests"], "Changed test totals")
        require(len(receipts) == result["executionGroups"], "Missing test execution group")
        require(all(receipt.get("presentation", "headless") == "headless" for receipt in receipts), "Unexpected visible test")


def expect_rejection(operation) -> None:
    try:
        operation()
    except (ValueError, KeyError):
        return
    raise AssertionError("Negative control was accepted")


def negative_controls(root: Path, receipts) -> None:
    run = root / "tools-baseline-11"
    configuration = read_json(run / "run.json")
    jobs = receipts.planned_jobs(configuration)
    record = read_json(next(run.glob("*/cases/*.json")))
    for mutation in ("reply", "score"):
        changed = copy.deepcopy(record)
        if mutation == "reply":
            changed["turns"][0]["reply"] += " changed"
        else:
            changed["passed"] = not changed["passed"]
        expect_rejection(lambda: receipts.validate(changed, jobs[changed["job"]], changed["model"]))
    altered_corpus = copy.deepcopy(configuration)
    altered_corpus["cases"][0]["turns"][0]["user"] += " changed"
    expect_rejection(lambda: receipts.planned_jobs(altered_corpus))
    voice = read_json(root / "voice-measured-kokoro-82m-en-0/spoken-answer.json")
    for mutation in ("missing", "duplicate", "incomplete"):
        changed = copy.deepcopy(voice)
        phrases = changed["observations"][1]["spokenPhrases"]
        if mutation == "missing":
            phrases.pop()
        elif mutation == "duplicate":
            phrases.append(phrases[0])
        else:
            changed["observations"].pop()
        expect_rejection(lambda: validate_voice(changed, "kokoro-82m-en"))


def main() -> None:
    archive = read_compressed("raw-evidence.json.gz")
    with tempfile.TemporaryDirectory(prefix="sillies-chat-voice-audit-") as temporary:
        root = Path(temporary)
        materialize(archive, root)
        sys.path.insert(0, str(root / "evaluator"))
        from evaluation import receipts
        actual = {
            "chat": chat_statistics(root, receipts), "voice": voice_statistics(root),
            "endpoint": endpoint_statistics(root), "budget": budget_statistics(root),
        }
        require(actual == read_compressed("results.json.gz"), "Published measurements do not reproduce")
        validate_reviews(root, read_compressed("manual-review.json.gz"))
        validate_application_receipts(root)
        negative_controls(root, receipts)
    print(f"Verified {len(actual['chat'])} Chat runs, three voice pairs, 60 endpoint clips, reviews and 44 execution receipts.")
    print("Published measurements reproduce; six deliberately broken controls were rejected.")


if __name__ == "__main__":
    main()
