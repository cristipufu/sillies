"""Opt-in performance selection, independent of native presentation and completion evidence."""
import json
from pathlib import Path

from test_evidence import IncompleteTestRun, swift_test_name

MAXIMUM_TESTS_PER_PROCESS = 64


def swift_test_batches(tests, parameterized, maximum_tests=MAXIMUM_TESTS_PER_PROCESS):
    """Keep matrices intact, and bound ordinary groups without extending any watchdog."""
    if maximum_tests <= 0:
        raise ValueError("A test batch must have positive capacity")
    tests = set(tests)
    matrices = tests & set(parameterized)
    ordinary = sorted(tests - matrices)
    batches = [set(ordinary[start:start + maximum_tests])
               for start in range(0, len(ordinary), maximum_tests)]
    return batches + [{test} for test in sorted(matrices)]


def unique_fields(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise IncompleteTestRun(f"Duplicate performance classification: {key}")
        result[key] = value
    return result


class TestSuites:
    def __init__(self, path=Path("Tests/performance-tests.json")):
        self.rules = json.loads(path.read_text(), object_pairs_hook=unique_fields)
        if not isinstance(self.rules, dict) or set(self.rules) != {"swift-testing", "xctest"}:
            raise IncompleteTestRun("Performance classifications need both test frameworks")
        for framework, bundles in self.rules.items():
            if not isinstance(bundles, dict):
                raise IncompleteTestRun(f"Invalid performance bundles for {framework}")
            for bundle, tests in bundles.items():
                if not isinstance(tests, dict) or not tests:
                    raise IncompleteTestRun(f"Invalid performance tests for {bundle}")
                for name, reason in tests.items():
                    if not name.startswith(bundle + ".") or not isinstance(reason, str) or not reason.strip():
                        raise IncompleteTestRun(f"Performance test needs an exact name and reason: {name}")

    def validate_bundles(self, available):
        configured = set().union(*(bundles.keys() for bundles in self.rules.values()))
        if missing := configured - set(available):
            raise IncompleteTestRun(f"Stale performance bundles: {sorted(missing)}")

    def partition(self, bundle, framework, discovered):
        rules = self.rules[framework].get(bundle, {})
        name = swift_test_name if framework == "swift-testing" else lambda value: value
        stale = set(rules) - {name(identifier) for identifier in discovered}
        if stale:
            raise IncompleteTestRun(f"Stale performance tests in {bundle}: {sorted(stale)}")
        performance = {identifier for identifier in discovered if name(identifier) in rules}
        return dict(standard=set(discovered) - performance, performance=performance,
                    all=set(discovered))


def test_batches(bundles):
    """Every bundle, including future targets, belongs to exactly one bounded batch."""
    isolated = ["SilliesAudioTests", "SilliesPersistenceTests", "SilliesAppTests"]
    groups = [[bundle for bundle in bundles if bundle.stem not in isolated]]
    groups.extend([bundle for bundle in bundles if bundle.stem == name] for name in isolated)
    return [group for group in groups if group]
