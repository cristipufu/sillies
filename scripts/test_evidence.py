"""Completion accounting independent of subprocess exit codes and human Swift Testing names."""
import json
import re
from collections import Counter


class IncompleteTestRun(ValueError):
    pass


def event_records(path):
    with open(path, encoding="utf-8") as stream:
        for line in stream:
            record = json.loads(line)
            if record.get("version") != 0:
                raise IncompleteTestRun("Unsupported Swift Testing event format")
            yield record


def swift_inventory(path):
    return {record["payload"]["id"] for record in event_records(path)
            if record["kind"] == "test" and record["payload"]["kind"] == "function"}


def swift_test_name(identifier):
    # Source locations disambiguate overloads in receipts, but are not part of SwiftPM filters.
    return re.sub(r"/[^/]+\.swift:\d+:\d+$", "", identifier)


def selected_tests(identifiers, filters, skips, name=lambda value: value):
    return {identifier for identifier in identifiers
            if (not filters or any(re.search(pattern, name(identifier)) for pattern in filters))
            and not any(re.search(pattern, name(identifier)) for pattern in skips)}


def verify_swift_run(path, expected):
    records = list(event_records(path))
    actual = {record["payload"]["id"] for record in records
              if record["kind"] == "test" and record["payload"]["kind"] == "function"}
    if actual - expected:
        raise IncompleteTestRun(f"Unselected tests ran: {sorted(actual - expected)}")
    events = [record["payload"] for record in records if record["kind"] == "event"]
    kinds = Counter(event["kind"] for event in events)
    if kinds["runStarted"] != 1 or kinds["runEnded"] != 1:
        raise IncompleteTestRun("Swift Testing did not finish exactly one test run")
    completed = Counter(event.get("testID") for event in events
                        if event["kind"] in {"testEnded", "testSkipped"})
    invalid = {identifier for identifier in expected if completed[identifier] != 1}
    if invalid:
        raise IncompleteTestRun(f"Missing or duplicate test receipts: {sorted(invalid)}")
    if any(message.get("symbol") == "fail" for event in events for message in event.get("messages", [])):
        raise IncompleteTestRun("Swift Testing reported a failure")
    return len(expected)


def xctest_inventory(node, parent=""):
    if "tests" not in node:
        return {parent + "/" + node["name"]}
    return set().union(*(xctest_inventory(child, node["name"]) for child in node["tests"]))


def verify_xctest_run(log, expected):
    finished = Counter(f"{suite}/{method}" for suite, method, _ in re.findall(
        r"Test Case '-\[([^ ]+) ([^\]]+)\]' (passed|skipped) ", log))
    invalid = {identifier for identifier in expected if finished[identifier] != 1}
    if invalid:
        raise IncompleteTestRun(f"Missing or duplicate XCTest receipts: {sorted(invalid)}")
    if not re.search(r"Test Suite '(?:All tests|Selected tests)' passed", log):
        raise IncompleteTestRun("XCTest did not report a successful completed run")
    if re.search(r"Test Case .* failed", log):
        raise IncompleteTestRun("XCTest reported a failure")
    return len(expected)
