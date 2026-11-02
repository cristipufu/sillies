"""Bind judgments to the observed task, actions and state, not just fluent reply text."""
from __future__ import annotations

import hashlib

from .corpus import digest


def response_hash(turn: dict) -> str:
    return hashlib.sha256((turn.get("reply") or "").encode()).hexdigest()


def review_hash(turn: dict) -> str:
    derived = {"checks", "responseHash", "evidenceHash"}
    return digest({key: value for key, value in turn.items() if key not in derived})


def seal(result: dict) -> dict:
    for turn in result["turns"]:
        turn["evidenceHash"] = review_hash(turn)
    return result
