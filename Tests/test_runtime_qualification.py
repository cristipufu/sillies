"""Negative controls for qualification, paired comparisons, and private-data-free exports."""
import copy
import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "Benchmarks/Chat"))
from evaluation import calibration, portable

spec = importlib.util.spec_from_file_location("qualification", ROOT / "scripts/check-runtime-qualifications.py")
qualification = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qualification)


class RuntimeQualificationTests(unittest.TestCase):
    def setUp(self):
        self.catalog = json.loads((ROOT / "Sources/SilliesModelStore/Resources/text-models.json").read_text())
        self.matrix = json.loads((ROOT / "ModelProfiles/runtime-qualifications.json").read_text())

    def test_shipping_profiles_match_their_evidence(self):
        qualification.validate(ROOT, self.catalog, self.matrix)

    def test_catalog_changes_missing_rows_and_edited_evidence_fail(self):
        changed = copy.deepcopy(self.catalog)
        changed["manifests"][0]["model"]["profile"]["prefill"] = {"chunkTokens": 37}
        with self.assertRaises(ValueError): qualification.validate(ROOT, changed, self.matrix)
        missing = copy.deepcopy(self.matrix)
        missing["models"].pop()
        with self.assertRaises(ValueError): qualification.validate(ROOT, self.catalog, missing)
        altered = copy.deepcopy(self.matrix)
        altered["models"][0]["evidence"][0]["sha256"] = "0" * 64
        with self.assertRaises(ValueError): qualification.validate(ROOT, self.catalog, altered)

    def test_new_misses_cannot_be_offset_by_gains_elsewhere(self):
        baseline = {"cases": [{"job": "one", "turns": [{"reply": "yes", "checks": [{"passed": True}, {"passed": False}]}]}],
                    "reviews": {("one", 0): {"verdict": "pass"}}}
        candidate = copy.deepcopy(baseline)
        candidate["cases"][0]["turns"][0]["checks"] = [{"passed": False}, {"passed": True}]
        self.assertEqual(calibration.regressions(baseline, candidate), 1)
        candidate = copy.deepcopy(baseline)
        candidate["reviews"][("one", 0)]["verdict"] = "fail"
        self.assertEqual(calibration.regressions(baseline, candidate), 1)
        candidate["cases"][0]["job"] = "different"
        with self.assertRaises(ValueError): calibration.regressions(baseline, candidate)

    def test_hardware_export_ignores_extra_private_fields_and_rejects_embedded_paths(self):
        source = {"processor": "Apple M4 Pro", "memoryBytes": 48 * 1024**3, "logicalProcessors": 12,
                  "osVersion": "27.1", "osBuild": "26B118", "architecture": "arm64",
                  "user": "private name", "home": "/Users/private", "prompt": "a private message"}
        exported = portable.machine(source)
        self.assertNotIn("private", json.dumps(exported))
        source["processor"] = "Apple M4 Pro /Users/private"
        with self.assertRaises(ValueError): portable.machine(source)

    def test_prefill_requires_identical_conditions_and_only_changes_batching(self):
        before, after = comparison()
        self.assertEqual(calibration.compare(before, after)["chunkTokens"], 1024)
        for key in calibration.MATCHED_FIELDS:
            changed = copy.deepcopy(after)
            changed["configuration"][key] = "different"
            with self.subTest(field=key), self.assertRaises(ValueError):
                calibration.compare(before, changed)
        for latency in (0, -1, float("nan"), float("inf"), 9.1):
            changed = copy.deepcopy(after)
            changed["result"]["primary"]["firstTextP50"] = latency
            with self.subTest(latency=latency), self.assertRaises(ValueError):
                calibration.compare(before, changed)
        after["metadata"]["profile"]["context"] = "different"
        with self.assertRaises(ValueError): calibration.compare(before, after)

    def test_portable_report_uses_allowlist_for_complete_export(self):
        private = "PRIVATE PROMPT /Users/private/home"
        configuration = {key: "a" * 64 for key in
                         ("corpusHash", "catalogHash", "workerHash", "helperHash", "evaluatorHash")}
        configuration.update(repeats=2, prefillChunkTokens=None, prompt=private,
                             machine={"processor": "Apple M4 Pro", "memoryBytes": 48 * 1024**3,
                                      "logicalProcessors": 12, "osVersion": "27.1", "osBuild": "26B118",
                                      "architecture": "arm64", "home": private})
        result = {"primary": {"cases": 1, "passed": 1, "turns": 1, "errors": 0,
                              "checks": {"behavior": {"passed": 1, "total": 1}},
                              "firstTextP50": 1, "firstTextP95": 1, "totalP50": 2, "reply": private},
                  "pendingPrimaryCases": 0,
                  "semanticReviews": {"primaryRubricReviewedTurns": 1, "rubricCases": {"pass": 1},
                                      "reviewer": private}, "toolResult": private}
        summary = {"configuration": configuration, "models": {"apple": result}, "messages": private}
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "apple").mkdir()
            (root / "apple/model.json").write_text(json.dumps({"revision": "system-managed", "path": private}))
            with patch.object(portable.report, "generate", return_value=summary) as recompute:
                exported = portable.generate(root)
                recompute.assert_called_once_with(root)
            self.assertNotIn("PRIVATE", json.dumps(exported))
            self.assertNotIn("/Users/", json.dumps(exported))
            self.assertEqual(exported["models"][0]["completedCases"], 1)
            with patch.object(portable.report, "generate", side_effect=ValueError("bad evidence")):
                with self.assertRaises(ValueError): portable.generate(root)

    def test_missing_uncertain_or_reply_only_reviews_cannot_qualify(self):
        model = "qwen-3.5-4b"
        cases = [{"job": str(index), "case": str(index), "profile": "app", "group": group,
                  "turns": [{"reply": "Synthetic"}]} for index, group in
                 enumerate(("identity", "memories", "vault", "mixed-knowledge", "memories", "vault"))]
        judgments = [{"model": model, "job": case["job"], "turn": 0, "scope": "rubric",
                      "evidenceHash": "checked upstream", "verdict": "pass"} for case in cases]
        summary = {"configuration": {"models": [model], "repeats": 2, "cases": cases},
                   "models": {model: {"pendingPrimaryCases": 0, "primary": {"cases": 6}}}}
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / model).mkdir()
            (root / model / "model.json").write_text("{}")
            def load(entries):
                (root / "reviews.json").write_text(json.dumps(entries))
                with patch.object(calibration.report, "generate", return_value=summary), \
                        patch.object(calibration.receipts, "load", return_value={model: cases}):
                    return calibration.load_run(root, model)
            self.assertEqual(len(load(judgments)["cases"]), 6)
            with self.assertRaises(ValueError): load(judgments[:-1])
            for field, value in (("scope", "reply"), ("verdict", "uncertain")):
                changed = copy.deepcopy(judgments)
                changed[0][field] = value
                with self.subTest(field=field), self.assertRaises(ValueError): load(changed)
            summary["models"][model]["pendingPrimaryCases"] = 1
            with self.assertRaises(ValueError): load(judgments)


def comparison():
    configuration = dict.fromkeys(calibration.MATCHED_FIELDS, "same")
    configuration.update(prefillChunkTokens=None, cases=list(range(6)), repeats=2, corpusHash="a" * 64)
    profile = {"prefill": {"chunkTokens": None}, "context": "unchanged"}
    baseline = {"configuration": configuration,
                "metadata": {"calibrationIdentity": {"profile": profile}, "profile": profile},
                "result": {"primary": {"firstTextP50": 10, "turns": 12}},
                "cases": [{"job": "one", "turns": [{"reply": "ok", "checks": [{"passed": True}]}]}],
                "reviews": {("one", 0): {"verdict": "pass"}}}
    candidate = copy.deepcopy(baseline)
    candidate["configuration"]["prefillChunkTokens"] = 1024
    candidate["metadata"]["profile"] = dict(profile, prefill={"chunkTokens": 1024})
    candidate["result"]["primary"]["firstTextP50"] = 8
    return baseline, candidate


if __name__ == "__main__":
    unittest.main()
