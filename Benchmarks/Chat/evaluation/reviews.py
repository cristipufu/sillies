"""Human semantic judgments stay separate from automated checks and bind to exact replies."""
from __future__ import annotations

import json
from pathlib import Path


def load(output: Path, results: dict[str, list[dict]]) -> dict[str, dict]:
    path = output / "reviews.json"
    if not path.exists():
        return {}
    known = {(model, result["job"], index): turn
             for model, cases in results.items() for result in cases
             for index, turn in enumerate(result["turns"])}
    seen = set()
    summary = {}
    for review in json.loads(path.read_text()):
        key = review["model"], review["job"], review["turn"]
        if key in seen or key not in known:
            raise ValueError(f"Duplicate or unknown semantic review: {key}")
        seen.add(key)
        if review["responseHash"] != known[key]["responseHash"]:
            raise ValueError(f"Semantic review refers to an outdated response: {key}")
        if review["verdict"] not in {"pass", "fail", "uncertain"} or not review.get("note", "").strip():
            raise ValueError(f"A semantic review needs a verdict and rationale: {key}")
        counts = summary.setdefault(review["model"], {"pass": 0, "fail": 0, "uncertain": 0})
        counts[review["verdict"]] += 1
    return summary
