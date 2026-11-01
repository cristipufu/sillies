"""Explicit execution modes for native tests; every discovered source needs a classification."""
import json
from pathlib import Path

from test_evidence import IncompleteTestRun, swift_test_name


class TestPresentation:
    def __init__(self, path=Path("Tests/SilliesAppTests/execution-modes.json")):
        self.files = json.loads(path.read_text())

    def partition(self, identifiers):
        groups = {"headless": set(), "gui": set()}
        seen = {}
        for identifier in identifiers:
            source = identifier.rsplit("/", 1)[-1].split(":", 1)[0]
            name = swift_test_name(identifier).split(".", 1)[-1]
            policy = self.files.get(source)
            if not isinstance(policy, dict):
                raise IncompleteTestRun(f"Classify new native test source {source} in execution-modes.json")
            seen.setdefault(source, set()).add(name)
            mode = policy.get("tests", {}).get(name, policy.get("default"))
            if mode not in groups:
                raise IncompleteTestRun(f"Invalid presentation mode for {identifier}: {mode}")
            groups[mode].add(identifier)
        for source, policy in self.files.items():
            if source not in seen:
                raise IncompleteTestRun(f"Stale native test source classification: {source}")
            stale = set(policy.get("tests", {})) - seen[source]
            if stale:
                raise IncompleteTestRun(f"Stale native test classifications in {source}: {sorted(stale)}")
        return groups
