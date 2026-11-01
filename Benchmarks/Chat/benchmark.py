#!/usr/bin/env python3
"""Run bounded, resumable evaluations of Sillies' native local Chat providers."""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from evaluation import archive, corpus, environment, report
from evaluation.runner import ModelBatch
from evaluation.storage import file_hash, initialize

ROOT = Path(__file__).resolve().parents[2]


def arguments():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("validate", "fixtures", "run", "report", "export"))
    parser.add_argument("--archive", type=Path)
    parser.add_argument("--corpus", type=Path, default=Path(__file__).parent / "cases")
    parser.add_argument("--output", type=Path, default=ROOT / "build/chat-benchmark")
    parser.add_argument("--worker", type=Path, default=ROOT / ".build/out/Products/Debug/ChatModelBenchmark")
    parser.add_argument("--helper", type=Path, default=ROOT / "build/Sillies.app/Contents/Helpers/SilliesTextInference.app/Contents/MacOS/SilliesTextInference")
    parser.add_argument("--models-root", type=Path, default=Path.home() / "Library/Application Support/Sillies/TextModels")
    parser.add_argument("--models", nargs="+", default=["apple"])
    parser.add_argument("--groups", nargs="+")
    parser.add_argument("--tag")
    parser.add_argument("--repeats", type=int, default=1)
    parser.add_argument("--max-seconds", type=float, default=180)
    parser.add_argument("--turn-timeout", type=float, default=60)
    parser.add_argument("--case-timeout", type=float, default=180)
    parser.add_argument("--startup-timeout", type=float, default=90)
    options = parser.parse_args()
    if not 1 <= options.repeats <= 5 or not 5 <= options.max_seconds <= 1800:
        parser.error("Use 1–5 repeats and a batch budget of 5–1800 seconds")
    if not all(5 <= value <= 300 for value in (options.turn_timeout, options.case_timeout, options.startup_timeout)):
        parser.error("Process deadlines must be 5–300 seconds")
    return options


def main() -> None:
    options = arguments()
    if options.command in {"report", "export"}:
        report.generate(options.output)
        if options.command == "export":
            if options.archive is None:
                raise ValueError("Export requires --archive PATH.json.gz")
            archive.export(options.output, options.archive)
        return
    cases = corpus.load(options.corpus)
    if options.groups:
        cases = [case for case in cases if case["group"] in options.groups]
    if options.tag:
        cases = [case for case in cases if options.tag in case.get("tags", [])]
    if not cases:
        raise ValueError("The selected corpus is empty")
    jobs = corpus.jobs(cases, options.repeats)
    print(f"{len(cases)} scenarios · {len(jobs)} model cases · {sum(len(job['case']['turns']) for job in jobs)} turns per model", flush=True)
    if options.command == "validate":
        return
    if options.command == "fixtures":
        with tempfile.TemporaryDirectory(prefix="sillies-fixtures-") as workspace:
            plan = {"model": "apple", "modelDirectory": str(options.models_root),
                    "helper": str(options.helper), "workspace": workspace,
                    "jobs": [corpus.worker_job(job) for job in jobs]}
            plan_path = Path(workspace) / "plan.json"
            plan_path.write_text(json.dumps(plan))
            subprocess.run([str(options.worker), "--validate-fixtures", str(plan_path)], check=True, timeout=60)
        return
    catalog = json.loads((ROOT / "Sources/SilliesModelStore/Resources/text-models.json").read_text())
    supported = {"apple"} | {manifest["model"]["id"] for manifest in catalog["manifests"]}
    if len(set(options.models)) != len(options.models) or not set(options.models) <= supported:
        raise ValueError("Choose unique model IDs from the bundled text catalog, or apple")
    configuration = {"schema": 1, "corpusHash": corpus.digest(cases), "catalogHash": corpus.digest(catalog),
                     "workerHash": file_hash(options.worker), "helperHash": file_hash(options.helper),
                     "evaluatorHash": corpus.digest({str(path.relative_to(Path(__file__).parent)): file_hash(path)
                                                     for path in sorted(Path(__file__).parent.rglob("*.py"))}),
                     "python": sys.version, "machine": environment.capture(),
                     "sourceCommit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
                     "models": options.models, "repeats": options.repeats,
                     "turnTimeout": options.turn_timeout, "caseTimeout": options.case_timeout,
                     "startupTimeout": options.startup_timeout,
                     "jobs": [{"id": job["id"], "profile": job["profile"]} for job in jobs]}
    initialize(options.output, configuration)
    deadline = time.monotonic() + options.max_seconds
    try:
        for model in options.models:
            if time.monotonic() >= deadline:
                break
            ModelBatch(options, model, jobs, deadline).run()
    finally:
        report.generate(options.output)
    print(f"Results: {options.output / 'report.md'}; rerun the same command to resume incomplete cases.", flush=True)


if __name__ == "__main__":
    main()
