"""Objective behavior checks, exact-answer cases and explicitly limited lexical anchors."""
from __future__ import annotations

import hashlib
import json
import re


def canonical(text: str) -> str:
    return re.sub(r"\s+", " ", text.casefold()).strip(" \t\n.!?\"'`*")


def check_rule(rule: dict, turn: dict, tools: list[dict]) -> dict:
    kind = rule["kind"]
    values = rule.get("values", [])
    reply = turn.get("reply") or ""
    folded = reply.casefold()
    names = {tool["name"] for tool in tools}
    facts = [fact["value"].casefold() for fact in turn.get("memories", [])]
    observed: object = reply
    category = "behavior"
    if kind == "reply_equals":
        passed = canonical(reply) in {canonical(value) for value in values}
        category = "exact_answer"
    elif kind in {"contains_any", "contains_all", "omits_all"}:
        matches = [value.casefold() in folded for value in values]
        passed = any(matches) if kind == "contains_any" else all(matches) if kind == "contains_all" else not any(matches)
        category = "lexical_anchor"
    elif kind == "no_tools":
        passed, observed = not tools, sorted(names)
    elif kind == "tool_calls_at_most":
        passed, observed = len(tools) <= int(values[0]), len(tools)
    elif kind == "required_tools":
        passed, observed = set(values) <= names, sorted(names)
    elif kind == "allowed_tools":
        passed, observed = names <= set(values), sorted(names)
    elif kind == "no_writes":
        passed, observed = not names.intersection({"save_memory", "replace_memory"}), sorted(names)
    elif kind == "argument_equals":
        actual = []
        for tool in tools:
            if tool["name"] == rule["tool"]:
                try:
                    actual.append(json.loads(tool["arguments"]).get(rule["field"]))
                except (ValueError, AttributeError):
                    actual.append(None)
        passed, observed = any(value in values for value in actual), actual
    elif kind in {"memory_contains", "memory_absent"}:
        present = any(value.casefold() in fact for value in values for fact in facts)
        matches = present if kind == "memory_contains" else not present
        passed, observed = isinstance(turn.get("memories"), list) and matches, facts
    elif kind == "source_includes":
        observed = turn.get("sources", [])
        passed = {value.casefold() for value in values} <= {value.casefold() for value in observed}
    elif kind == "source_equals":
        observed = turn.get("sources")
        passed = isinstance(observed, list) and sorted(value.casefold() for value in values) == sorted(value.casefold() for value in observed)
    elif kind == "compacted":
        passed, observed = bool(turn.get("compacted")), turn.get("compacted", False)
    elif kind == "compaction_calls_at_most":
        observed = turn.get("compactionCalls")
        passed = isinstance(observed, int) and 0 <= observed <= int(values[0])
    elif kind in {"retained_context_omits", "initial_context_omits"}:
        requests = turn.get("requests", [])
        request = requests[0 if kind == "initial_context_omits" else -1] if requests else None
        observed = [message["content"] for message in request["messages"]] if request else []
        if request and kind == "initial_context_omits":
            observed = [request.get("instructions", "")] + observed
        passed = bool(requests) and all(value.casefold() not in text.casefold() for value in values for text in observed)
    else:
        raise ValueError(f"Unknown scoring rule: {kind}")
    # A failed generation can never pass a rule merely because its missing response omits a word.
    passed = bool(passed and not turn.get("error") and reply.strip())
    return {"kind": kind, "category": category, "passed": passed, "expected": values, "observed": observed}


def evaluate(job: dict, events: list[dict], failure: str | None) -> dict:
    turns = []
    for index, expected in enumerate(job["case"]["turns"]):
        observed = next((event["payload"] for event in events
                         if event["event"] == "turn" and event["payload"]["position"]["turn"] == index), None)
        calls = [event["payload"] for event in events
                 if event["event"] == "tool" and event["payload"]["position"]["turn"] == index]
        if observed is None:
            observed = {"position": {"job": job["id"], "turn": index}, "input": expected["user"],
                        "error": failure or "Turn did not complete", "reply": None}
        checks = [{"kind": "completed", "category": "behavior", "passed": not observed.get("error") and bool((observed.get("reply") or "").strip()),
                   "observed": observed.get("error")},
                  {"kind": "tool_execution", "category": "behavior", "passed": not any(call.get("error") for call in calls),
                   "observed": [call["error"] for call in calls if call.get("error")]}]
        checks.extend(check_rule(rule, observed, calls) for rule in expected.get("checks", []))
        turns.append({**observed, "calls": calls, "checks": checks, "rubric": expected["rubric"],
                      "responseHash": hashlib.sha256((observed.get("reply") or "").encode()).hexdigest()})
    return {"job": job["id"], "case": job["case"]["id"], "group": job["case"]["group"],
            "profile": job["profile"], "repeat": job["repeat"], "error": failure, "turns": turns,
            "passed": failure is None and all(check["passed"] for turn in turns for check in turn["checks"])}
