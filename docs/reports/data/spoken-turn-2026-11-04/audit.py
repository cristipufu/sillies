"""Audit timing receipts independently of the Swift runner; never score answer quality here."""
import copy
import gzip
import json
import math
import pathlib
import sys


def require(condition, message):
    if not condition:
        raise ValueError(message)


def finite(value):
    return type(value) in (float, int) and math.isfinite(value)


def request(record):
    rate = record["sampleRate"]
    chunks = record["chunks"]
    require(type(rate) is int and rate > 0 and chunks, "Missing audio")
    require(type(record["sampleCount"]) is int and record["sampleCount"] > 0, "Invalid sample count")
    require(record["sampleCount"] == sum(c["samples"] for c in chunks), "Dropped sample count")
    require(finite(record["elapsedSeconds"]), "Invalid completion time")
    end = None
    previous = 0
    previous_arrival = 0
    gaps = 0
    for chunk in chunks:
        arrival, accepted = chunk["arrived"], chunk["accepted"]
        require(finite(arrival) and finite(accepted), "Invalid chunk time")
        require(0 <= arrival <= accepted <= record["elapsedSeconds"], "Invalid timing order")
        require(previous_arrival <= arrival and previous <= accepted, "Invalid chunk sequence")
        require(type(chunk["samples"]) is int and chunk["samples"] > 0, "Invalid chunk count")
        if end is not None:
            gaps += max(0, accepted - end)
        end = max(end if end is not None else accepted, accepted) + chunk["samples"] / rate
        previous = accepted
        previous_arrival = arrival
    require(math.isclose(gaps, record["simulatedPlaybackGapSeconds"], abs_tol=1e-8), "Wrong gap total")
    digest = record["pcmSHA256"]
    require(len(digest) == 64 and all(c in "0123456789abcdef" for c in digest), "Invalid PCM digest")


def audit(evidence):
    for name in ("english", "mixed"):
        signatures = set()
        revisions = set()
        for arm in ("baseline", "deferred"):
            profile = evidence["profiles"][f"pcm-{name}-{arm}"]
            require(len(profile["requests"]) == 5, "Incomplete PCM comparison")
            revisions.add(profile["revision"])
            for record in profile["requests"]:
                request(record)
                signatures.add((record["pcmSHA256"], record["sampleCount"], record["sampleRate"]))
        require(len(signatures) == 1 and len(revisions) == 1, "Non-equivalent audio comparison")
    require(len(evidence["overlap"]) == 7, "Incomplete overlap matrix")
    for profile in evidence["overlap"].values():
        observations = profile["observations"]
        require([r["schedule"] for r in observations] == ["sequential", "sequential", "overlapping", "overlapping", "sequential"], "Incomplete overlap run")
        require(len({r["text"] for r in observations}) == 1, "Changed text workload")
        for record in observations:
            request(record["audio"])
            first, finished, total = (record[k] for k in ("firstTextSeconds", "textSeconds", "totalSeconds"))
            require(all(finite(v) for v in (first, finished, total)), "Invalid text timing")
            require(0 <= first <= finished <= total, "Invalid text timing order")
            submitted = record["synthesisRequestedSeconds"]
            audio = record["audio"]
            require(submitted <= audio["chunks"][0]["arrived"] <= audio["elapsedSeconds"] <= total, "Invalid audio ordering")
            threshold = finished if record["schedule"] == "sequential" else first
            require(submitted >= threshold, "Incorrect admission condition")
        if profile["voiceModel"] in ("fish-s2-pro-8bit", "kokoro-82m-en"):
            require(len({r["audio"]["pcmSHA256"] for r in observations}) == 1, "Changed deterministic audio")
    print("Audited 20 PCM requests and 35 overlap observations; stochastic voice durations remain unpaired.")


def self_test():
    valid = dict(sampleRate=10, sampleCount=6, elapsedSeconds=0.6, pcmSHA256="0" * 64,
                 simulatedPlaybackGapSeconds=0.2, chunks=[
                     dict(arrived=0.0, accepted=0.0, samples=3),
                     dict(arrived=0.5, accepted=0.5, samples=3)])
    request(valid)
    malformed = []
    for key, value in (("sampleCount", 7), ("simulatedPlaybackGapSeconds", 0),
                       ("elapsedSeconds", float("nan")), ("pcmSHA256", "missing")):
        changed = copy.deepcopy(valid)
        changed[key] = value
        malformed.append(changed)
    changed = copy.deepcopy(valid)
    changed["chunks"][1]["accepted"] = 0.1
    malformed.append(changed)
    for changed in malformed:
        try:
            request(changed)
        except ValueError:
            continue
        raise ValueError("The audit accepted deliberately invalid evidence")
    print("Independent audit controls passed, including five deliberately broken receipts.")


if __name__ == "__main__":
    self_test()
    if "--self-test" not in sys.argv:
        path = pathlib.Path(__file__).with_name("results.json.gz")
        audit(json.loads(gzip.decompress(path.read_bytes())))
