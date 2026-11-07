"""Independent retrieval scoring. Invalid or incomplete runs cannot produce a score."""
import json
import math
from collections import defaultdict


def unique(items, identity):
    result = {}
    for item in items:
        key = item[identity]
        if key in result:
            raise ValueError(f"Duplicate {identity}: {key}")
        result[key] = item
    return result


def metrics(ranked, relevant, limit=5):
    grades = [relevant.get(identifier, 0) for identifier in ranked[:limit]]
    positive = {key for key, grade in relevant.items() if grade > 0}
    hits = sum(grade > 0 for grade in grades)
    dcg = sum((2 ** grade - 1) / math.log2(index + 2) for index, grade in enumerate(grades))
    ideal = sorted(relevant.values(), reverse=True)[:limit]
    idcg = sum((2 ** grade - 1) / math.log2(index + 2) for index, grade in enumerate(ideal))
    return {
        "hitAt5": float(hits > 0),
        "recallAt5": hits / len(positive) if positive else 0.0,
        "precisionAt5": hits / limit,
        "mrrAt5": next((1 / (index + 1) for index, grade in enumerate(grades) if grade > 0), 0.0),
        "ndcgAt5": dcg / idcg if idcg else 0.0,
    }


def eligible_documents(query, documents):
    scope = query.get("scope", "all")
    if scope not in {"all", "trash"}:
        raise ValueError("This corpus supports only all/trash scopes and tag filters")
    return {
        key for key, document in documents.items()
        if bool(document.get("trashed", False)) == (scope == "trash")
        and (not query.get("tag") or query["tag"] == document.get("tag"))
    }


def validate_elapsed(value):
    if type(value) not in (int, float) or not math.isfinite(value) or value < 0:
        raise ValueError("Invalid elapsed time")


def validate_ranking(ranked, eligible):
    if not isinstance(ranked, list) or any(not isinstance(item, str) for item in ranked):
        raise ValueError("A ranking must be a list of document IDs")
    if len(ranked) > 5 or len(ranked) != len(set(ranked)) or not set(ranked).issubset(eligible):
        raise ValueError("Unknown, duplicated, filtered-out or excess result")


def validate_exact_results(rows):
    uses_oracle = any("exactSemantic" in row or "exactSemanticSeconds" in row for row in rows)
    if not uses_oracle:
        return False
    for row in rows:
        if row.get("exactSemantic") is None or row.get("exactSemanticSeconds") is None:
            raise ValueError("An exact comparison requires a completed oracle result for every query")
        validate_elapsed(row["exactSemanticSeconds"])
    return True


def score(inputs, expected, rows):
    documents = unique(inputs["documents"], "id")
    queries = unique(inputs["queries"], "id")
    results = unique(rows, "id")
    if set(results) != set(queries) or set(expected) != set(queries):
        raise ValueError("Missing or unexpected query/expectation")
    uses_oracle = validate_exact_results(rows)
    groups = defaultdict(list)
    availability = defaultdict(int)
    overlaps = []
    for key, query in queries.items():
        row, gold = results[key], expected[key]
        eligible = eligible_documents(query, documents)
        relevant = gold["relevant"]
        if not set(relevant).issubset(eligible):
            raise ValueError("Expected document violates the query filter")
        if any(type(value) is not int or value <= 0 or value > 4 for value in relevant.values()):
            raise ValueError("Invalid relevance grade")
        for field in ("keywordSeconds", "semanticSeconds"):
            validate_elapsed(row[field])
        status = row["availability"]
        if status not in {"ready", "preparing", "unavailable", "changed", "timedOut"} and not status.startswith("failed("):
            raise ValueError("Unknown retrieval availability")
        availability[status] += 1
        methods = ["keywords", "semantic", "fused"]
        if uses_oracle:
            methods.append("exactSemantic")
        for method in methods:
            validate_ranking(row[method], eligible)
            groups[(gold["group"], method)].append((row[method], relevant))
        if uses_oracle:
            exact = set(row["exactSemantic"])
            if exact:
                overlaps.append(len(set(row["semantic"]) & exact) / len(exact))
    report = {}
    for (group, method), cases in sorted(groups.items()):
        positives = [metrics(ranked, relevant) for ranked, relevant in cases if relevant]
        negatives = [bool(ranked) for ranked, relevant in cases if not relevant]
        summary = {"queries": len(cases), "positiveQueries": len(positives), "absentQueries": len(negatives)}
        if positives:
            summary.update({name: sum(item[name] for item in positives) / len(positives) for name in positives[0]})
        if negatives:
            summary["absentQueriesReturningSuggestions"] = sum(negatives)
        report[f"{group}/{method}"] = summary
    return {"queries": len(queries), "documents": len(documents), "availability": dict(availability),
            "exactComparisonQueries": len(overlaps),
            "meanExactTop5Overlap": sum(overlaps) / len(overlaps) if overlaps else None, "groups": report}


def main():
    import argparse
    from pathlib import Path
    parser = argparse.ArgumentParser()
    parser.add_argument("inputs", type=Path)
    parser.add_argument("expected", type=Path)
    parser.add_argument("results", type=Path)
    args = parser.parse_args()
    rows = [json.loads(line) for line in args.results.read_text().splitlines()]
    print(json.dumps(score(json.loads(args.inputs.read_text()), json.loads(args.expected.read_text()), rows), indent=2))


if __name__ == "__main__":
    main()
