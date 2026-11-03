"""The benchmark must measure real behavior, retain failures, and keep gold out of inference."""
import json
import sys
import tempfile
import time
import unittest
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "Benchmarks/Chat"))
from evaluation import corpus, evidence, report, reviews, scoring
from evaluation.runner import ModelBatch
from evaluation.storage import initialize, record_model_metadata


def scenario():
    return {"id": "sample-case", "group": "identity", "profiles": ["app"],
            "turns": [{"user": "What is your name?", "rubric": "Hidden gold: Pogo, never Alex",
                       "checks": [{"kind": "reply_equals", "values": ["gold-only-token"]}]}]}


class ChatBenchmarkTests(unittest.TestCase):
    def test_gold_rubrics_and_expectations_never_enter_worker_inputs(self):
        job = corpus.jobs([corpus.validate(scenario())], 1)[0]
        encoded = json.dumps(corpus.worker_job(job))
        self.assertNotIn("gold-only-token", encoded)
        self.assertNotIn("Hidden gold", encoded)
        self.assertNotIn("checks", encoded)
        self.assertIn("What is your name?", encoded)

    def test_fixture_schema_rejects_unknown_checks_and_duplicate_profiles(self):
        bad = scenario()
        bad["turns"][0]["checks"][0]["kind"] = "always_pass"
        with self.assertRaises(ValueError):
            corpus.validate(bad)
        bad = scenario()
        bad["profiles"] = ["app", "app"]
        with self.assertRaises(ValueError):
            corpus.validate(bad)

    def test_lexical_match_does_not_count_as_exact_factual_answer(self):
        response = {"reply": "It is not Everest, it is Mars."}
        lexical = scoring.check_rule({"kind": "contains_any", "values": ["Everest"]}, response, [])
        exact = scoring.check_rule({"kind": "reply_equals", "values": ["Everest"]}, response, [])
        self.assertTrue(lexical["passed"])
        self.assertEqual(lexical["category"], "lexical_anchor")
        self.assertFalse(exact["passed"])

    def test_claiming_memory_is_saved_is_not_a_successful_write(self):
        response = {"reply": "I saved your name as Alex.", "memories": []}
        self.assertFalse(scoring.check_rule({"kind": "memory_contains", "values": ["Alex"]}, response, [])["passed"])
        self.assertFalse(scoring.check_rule({"kind": "required_tools", "values": ["save_memory"]}, response, [])["passed"])

    def test_no_writes_rejects_creation_and_replacement_attempts(self):
        for name in ("save_memory", "replace_memory"):
            with self.subTest(name=name):
                calls = [{"name": name, "arguments": "{}", "result": '{"status":"notSaved"}'}]
                self.assertFalse(scoring.check_rule({"kind": "no_writes"}, {"reply": "Done"}, calls)["passed"])

    def test_empty_vault_search_is_still_an_incorrect_tool_for_general_knowledge(self):
        tools = [{"name": "search_vault", "arguments": '{"query":"Everest","category":"all"}', "result": "[]"}]
        self.assertFalse(scoring.check_rule({"kind": "no_tools"}, {"reply": "Everest"}, tools)["passed"])
        self.assertFalse(scoring.check_rule({"kind": "argument_equals", "tool": "search_vault", "field": "category", "values": ["links"]}, {"reply": "Everest"}, tools)["passed"])

    def test_failed_and_missing_turns_never_pass_absence_checks(self):
        self.assertFalse(scoring.check_rule({"kind": "no_tools"}, {"error": "context limit"}, [])["passed"])
        job = corpus.jobs([scenario()], 1)[0]
        result = scoring.evaluate(job, [], "timeout")
        self.assertFalse(result["passed"])
        self.assertEqual(len(result["turns"]), 1)
        self.assertEqual(report.aggregate([result])["errors"], 1)

    def test_resume_rejects_a_changed_corpus_or_worker(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            initialize(path, {"corpusHash": "first", "workerHash": "abc"})
            initialize(path, {"corpusHash": "first", "workerHash": "abc"})
            with self.assertRaises(ValueError):
                initialize(path, {"corpusHash": "changed", "workerHash": "abc"})

    def test_documentation_commit_does_not_invalidate_identical_execution(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            initialize(path, {"workerHash": "abc", "sourceCommit": "before"})
            initialize(path, {"workerHash": "abc", "sourceCommit": "after"})
            self.assertEqual(json.loads((path / "run.json").read_text())["sourceCommit"], "before")

    def test_resume_rejects_changed_machine_conditions(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            original = {"workerHash": "abc", "machine": {"osBuild": "first", "memoryBytes": 48}}
            initialize(path, original)
            for machine in ({"osBuild": "new", "memoryBytes": 48}, {"osBuild": "first", "memoryBytes": 24}):
                with self.subTest(machine=machine), self.assertRaises(ValueError):
                    initialize(path, {**original, "machine": machine})
            self.assertEqual(json.loads((path / "run.json").read_text()), original)

    def test_model_metadata_cannot_be_overwritten_on_resume(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "model.json"
            original = {"revision": "first", "operatingSystem": "same"}
            record_model_metadata(path, original)
            record_model_metadata(path, original)
            for changed in ({"revision": "new", "operatingSystem": "same"},
                            {"revision": "first", "operatingSystem": "new"}):
                with self.subTest(metadata=changed), self.assertRaises(ValueError):
                    record_model_metadata(path, changed)
            self.assertEqual(json.loads(path.read_text()), original)

    def test_changed_worker_metadata_stops_before_admitting_a_case(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            marker = root / "admitted"
            worker = root / "worker.py"
            worker.write_text("#!/usr/bin/env python3\nimport json,sys,pathlib\n"
                              "print(json.dumps({'event':'model','payload':{'revision':'new'}}),flush=True)\n"
                              f"if sys.stdin.readline(): pathlib.Path({str(marker)!r}).touch()\n")
            worker.chmod(0o755)
            options = SimpleNamespace(output=root / "output", worker=worker, models_root=root,
                                      helper=worker, startup_timeout=1, case_timeout=1, turn_timeout=1)
            metadata = options.output / "apple/model.json"
            record_model_metadata(metadata, {"revision": "first"})
            ModelBatch(options, "apple", corpus.jobs([scenario()], 1), time.monotonic() + 5).run()
            self.assertFalse(marker.exists())
            self.assertEqual(json.loads(metadata.read_text()), {"revision": "first"})
            failure = json.loads((options.output / "apple/startup-failure.json").read_text())
            self.assertIn("environment changed", failure["error"])

    def test_semantic_reviews_reject_stale_responses_and_duplicate_votes(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            turn = {"reply": "Pogo"}
            results = {"apple": [{"job": "job", "profile": "app", "turns": [turn]}]}
            review = {"model": "apple", "job": "job", "turn": 0,
                      "responseHash": "old", "verdict": "pass", "note": "Factually correct"}
            (path / "reviews.json").write_text(json.dumps([review]))
            with self.assertRaises(ValueError):
                reviews.load(path, results)
            review["responseHash"] = evidence.response_hash(turn)
            (path / "reviews.json").write_text(json.dumps([review]))
            self.assertEqual(reviews.load(path, results)["apple"]["pass"], 1)
            (path / "reviews.json").write_text(json.dumps([review, review]))
            with self.assertRaises(ValueError):
                reviews.load(path, results)

    def test_hung_partial_output_is_killed_recorded_and_not_retried_on_resume(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            worker = root / "worker.py"
            worker.write_text("#!/usr/bin/env python3\nimport json,sys,time\np=json.load(open(sys.argv[1]))\nprint(json.dumps({'event':'model','payload':{'id':p['model']}}),flush=True)\ninput()\nprint(json.dumps({'event':'caseStarted','payload':p['jobs'][0]}),flush=True)\nsys.stdout.write('{\\\"event\\\":');sys.stdout.flush()\ntime.sleep(30)\n")
            worker.chmod(0o755)
            options = SimpleNamespace(output=root / "output", worker=worker, models_root=root,
                                      helper=worker, startup_timeout=1, case_timeout=.15, turn_timeout=.15)
            jobs = corpus.jobs([scenario()], 1)
            started = time.monotonic()
            ModelBatch(options, "apple", jobs, started + 10).run()
            receipt = options.output / "apple/cases/sample-case--app--r1.json"
            self.assertTrue(receipt.exists())
            result = json.loads(receipt.read_text())
            self.assertIn("deadline", result["error"])
            self.assertFalse(result["passed"])
            self.assertLess(time.monotonic() - started, 8)
            resumed = ModelBatch(options, "apple", jobs, time.monotonic() + 1)
            self.assertEqual(resumed.jobs, [])

    def test_shipped_corpus_contains_standalone_and_intertwined_knowledge(self):
        cases = corpus.load(ROOT / "Benchmarks/Chat/cases")
        groups = {case["group"] for case in cases}
        self.assertTrue({"general-knowledge", "vault", "mixed-knowledge", "identity", "memories", "context", "tool-scaling"} <= groups)
        self.assertGreaterEqual(len(cases), 50)
        profiles = {profile for case in cases for profile in case["profiles"]}
        self.assertEqual({corpus.PROFILES[profile] for profile in profiles}, {0, 1, 3, 5, 8, 12})

    def test_malformed_native_event_preserves_failed_case(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            worker = root / "worker.py"
            worker.write_text("#!/usr/bin/env python3\nimport json,sys\np=json.load(open(sys.argv[1]))\nprint(json.dumps({'event':'model','payload':{'id':p['model']}}),flush=True)\ninput()\nprint(json.dumps({'event':'caseStarted','payload':p['jobs'][0]}),flush=True)\nprint('{}',flush=True)\n")
            worker.chmod(0o755)
            options = SimpleNamespace(output=root / "output", worker=worker, models_root=root,
                                      helper=worker, startup_timeout=1, case_timeout=1, turn_timeout=1)
            ModelBatch(options, "apple", corpus.jobs([scenario()], 1), time.monotonic() + 5).run()
            result = json.loads((options.output / "apple/cases/sample-case--app--r1.json").read_text())
            self.assertFalse(result["passed"])
            self.assertIn("protocol failed", result["error"])


if __name__ == "__main__":
    unittest.main()
