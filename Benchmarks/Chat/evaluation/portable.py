"""Explicit allowlist export: no questions, replies, tool payloads, paths or reviewer identities."""
from __future__ import annotations

import json
import re
from pathlib import Path

from . import report

DIGEST = re.compile(r"[a-f0-9]{64}")
IDENTIFIER = re.compile(r"[a-z0-9][a-z0-9._-]{0,95}")


def checked_string(value: str, pattern: re.Pattern) -> str:
    if not isinstance(value, str) or not pattern.fullmatch(value):
        raise ValueError("Invalid portable metadata")
    return value


def machine(source: dict) -> dict:
    processor = checked_string(source["processor"], re.compile(r"Apple M[0-9]+(?: (?:Pro|Max|Ultra))?"))
    memory = source["memoryBytes"]
    processors = source["logicalProcessors"]
    if type(memory) is not int or not 0 < memory < 2**50 or type(processors) is not int or not 0 < processors < 1024:
        raise ValueError("Invalid hardware counts")
    return {"processor": processor, "memoryBytes": memory, "logicalProcessors": processors,
            "osVersion": checked_string(source["osVersion"], re.compile(r"[0-9]+(?:\.[0-9]+){1,2}")),
            "osBuild": checked_string(source["osBuild"], re.compile(r"[0-9]{2}[A-Z][0-9]+[a-z]?")),
            "architecture": checked_string(source["architecture"], re.compile(r"arm64|x86_64"))}


def generate(directory: Path) -> dict:
    summary = report.generate(directory)  # Recompute checks and validate full evidence before exporting totals.
    configuration = summary["configuration"]
    roots = Path(__file__).resolve().parents[3]
    catalog = json.loads((roots / "Sources/SilliesModelStore/Resources/text-models.json").read_text())
    known = {"apple"} | {item["model"]["id"] for item in catalog["manifests"]}
    models = []
    for identifier, result in summary["models"].items():
        if identifier not in known:
            raise ValueError("Portable reports require catalog model IDs")
        model = json.loads((directory / identifier / "model.json").read_text())
        revision = checked_string(model["revision"], re.compile(r"[a-f0-9]{40}|system-managed"))
        primary = result["primary"]
        models.append({"id": identifier, "revision": revision, "completedCases": primary["cases"],
                       "plannedCases": primary["cases"] + result["pendingPrimaryCases"],
                       "passedCases": primary["passed"], "turns": primary["turns"], "errors": primary["errors"],
                       "checks": primary["checks"], "firstTextP50": primary["firstTextP50"],
                       "firstTextP95": primary["firstTextP95"], "totalP50": primary["totalP50"],
                       "reviewedTurns": result["semanticReviews"]["primaryRubricReviewedTurns"],
                       "reviewedCases": result["semanticReviews"]["rubricCases"]})
    hashes = {key: checked_string(configuration[key], DIGEST)
              for key in ("corpusHash", "catalogHash", "workerHash", "helperHash", "evaluatorHash")}
    return {"version": 1, "scope": "synthetic-chat", "machine": machine(configuration["machine"]),
            "evidence": hashes, "prefillChunkTokens": configuration.get("prefillChunkTokens"),
            "repeats": configuration["repeats"], "models": models}
