#!/usr/bin/env python3
"""Reject unreviewed catalog/runtime changes and stale optimization evidence."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def digest(value: dict) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()


def validate(root: Path, catalog: dict, matrix: dict) -> None:
    if matrix.get("version") != 1:
        raise ValueError("Unsupported runtime qualification matrix")
    pins = json.loads((root / "Package.resolved").read_text())["pins"]
    runtime_dependencies = {"mlx-swift", "mlx-swift-lm", "swift-transformers"}
    actual = {pin["identity"]: pin["state"]["revision"] for pin in pins if pin["identity"] in runtime_dependencies}
    if actual != matrix.get("dependencies") or actual.keys() != runtime_dependencies:
        raise ValueError("Native runtime dependencies changed; renew qualification before shipping")
    models = {item["model"]["id"]: item["model"] for item in catalog["manifests"]}
    rows = {item["modelID"]: item for item in matrix["models"]}
    if len(rows) != len(matrix["models"]) or models.keys() != rows.keys():
        raise ValueError("Every catalog checkpoint needs one qualification record")
    for identifier, model in models.items():
        row = rows[identifier]
        expected = {"revision": model["revision"], "profileSHA256": digest(model["profile"]),
                    "runtimeRevision": model["profile"]["evidence"]["runtimeRevision"],
                    "cache": model["profile"].get("runtime", {}).get("conversationCache", "disabled"),
                    "reasoning": model.get("reasoning")}
        if any(row.get(key) != value for key, value in expected.items()):
            raise ValueError(f"Runtime profile changed without renewed qualification: {identifier}")
        if row["decision"] not in {"reviewed", "held"} or (row["cache"] != "disabled" and row["decision"] != "reviewed"):
            raise ValueError(f"An unqualified optimization is enabled: {identifier}")
        if not row["limitations"] or not row["evidence"]:
            raise ValueError(f"Missing review evidence or stated limits: {identifier}")
        for item in row["evidence"]:
            relative = Path(item["path"])
            if relative.is_absolute() or ".." in relative.parts or relative.parts[:2] != ("docs", "reports"):
                raise ValueError("Evidence must be a repository report")
            path = root / relative
            if hashlib.sha256(path.read_bytes()).hexdigest() != item["sha256"]:
                raise ValueError(f"Qualification evidence changed: {relative}")
    required = {"toolProtocol", "reasoningChannels", "cancellation", "cacheOwnership", "profileInvalidation"}
    if set(matrix["requiredChecks"]) != required:
        raise ValueError("Missing runtime qualification checks")
    for paths in matrix["requiredChecks"].values():
        if not paths or any(not (root / path).is_file() for path in paths):
            raise ValueError("A required qualification test is missing")


if __name__ == "__main__":
    catalog = json.loads((ROOT / "Sources/SilliesModelStore/Resources/text-models.json").read_text())
    matrix = json.loads((ROOT / "ModelProfiles/runtime-qualifications.json").read_text())
    validate(ROOT, catalog, matrix)
    print(f"Runtime qualification matrix: {len(matrix['models'])} checkpoint profiles match reviewed evidence.")
