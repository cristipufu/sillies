"""Publish the synthetic evidence needed to audit a comparison without committing huge log trees."""
from __future__ import annotations

import gzip
import json
from pathlib import Path

from . import receipts, report


def export(output: Path, destination: Path) -> None:
    configuration = json.loads((output / "run.json").read_text())
    document = {"configuration": configuration,
                "summary": report.generate(output), "models": {}}
    review_path = output / "reviews.json"
    document["reviews"] = json.loads(review_path.read_text()) if review_path.exists() else []
    results = receipts.load(output, configuration)
    for model in configuration["models"]:
        directory = output / model
        metadata = directory / "model.json"
        startup = directory / "startup-failure.json"
        document["models"][model] = {
            "metadata": json.loads(metadata.read_text()) if metadata.exists() else None,
            "startupFailure": json.loads(startup.read_text()) if startup.exists() else None,
            "cases": results[model],
        }
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix(destination.suffix + ".tmp")
    encoded = json.dumps(document, ensure_ascii=False, separators=(",", ":")).encode()
    temporary.write_bytes(gzip.compress(encoded, mtime=0))
    temporary.replace(destination)
