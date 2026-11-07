#!/usr/bin/env python3
"""Reproduce positive retrieval checks; this is not a precision/privacy or ANN recall score."""
import json
from pathlib import Path

DIRECTORY = Path(__file__).resolve().parent
REPOSITORY = DIRECTORY.parents[3]
FIXTURES = REPOSITORY / "Benchmarks/Chat/experiments/model-readiness-2026-11-04/semantic"


def score(filename, expected, known_documents):
    rows = [json.loads(line) for line in (DIRECTORY / filename).read_text().splitlines()]
    identities = [row["id"] for row in rows]
    assert len(identities) == len(set(identities)), "Duplicate query result"
    assert set(identities) == set(expected), "Missing or unexpected query"
    positive = hits = 0
    for row in rows:
        assert set(row["matches"]).issubset(known_documents), "Unknown result identity"
        assert len(row["matches"]) == len(set(row["matches"])), "Duplicated result identity"
        assert row["seconds"] >= 0, "Invalid elapsed time"
        wanted = set(expected[row["id"]]["expected"])
        assert wanted.issubset(known_documents), "Unknown expected document"
        if wanted:
            positive += 1
            hits += bool(wanted.intersection(row["matches"][:5]))
    return {"queries": len(rows), "positiveQueries": positive, "hitAt5": hits}


def main():
    expected = json.loads((FIXTURES / "expected.json").read_text())
    documents = {item["id"] for item in json.loads((FIXTURES / "inputs.json").read_text())["documents"]}
    for filename in ("semantic-native-e5.jsonl", "semantic-native-fusion.jsonl"):
        print(filename, json.dumps(score(filename, expected, documents), sort_keys=True))


if __name__ == "__main__":
    main()
