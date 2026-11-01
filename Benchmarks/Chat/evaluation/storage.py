"""Atomic receipts make interrupted benchmark batches resumable without losing failures."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path


def file_hash(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("w") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())
    temporary.replace(path)


def initialize(output: Path, configuration: dict) -> None:
    path = output / "run.json"
    if path.exists():
        previous = json.loads(path.read_text())
        # The binary/corpus hashes define execution. A later documentation commit changes neither.
        identity = lambda value: {key: item for key, item in value.items() if key != "sourceCommit"}
        if identity(previous) != identity(configuration):
            raise ValueError("This output belongs to a different corpus, binary, machine or configuration; use a new output folder")
    else:
        write_json(path, configuration)


def record_model_metadata(path: Path, metadata: dict) -> None:
    if path.exists():
        if json.loads(path.read_text()) != metadata:
            raise ValueError("Model revision or execution environment changed; use a new output folder")
        return
    write_json(path, metadata)
