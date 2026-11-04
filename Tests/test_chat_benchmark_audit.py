"""Adversarial evidence must not become a plausible model ranking."""
import copy
import json
import sys
import tempfile
import time
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "Benchmarks/Chat"))
from evaluation import archive, audit, corpus, environment, evidence, receipts, report, reviews, scoring
from evaluation.runner import ModelBatch
from evaluation.storage import initialize, write_json
from benchmark import scheduled_models


def sample_case(identifier="sample-case"):
    return {"id": identifier, "group": "knowledge", "profiles": ["app"],
            "turns": [{"user": "What is my address?", "rubric": "Do not invent an address.",
                       "checks": [{"kind": "no_writes"}]}]}


def receipt_for(case):
    job = corpus.jobs([case], 1)[0]
    observed = {"position": {"job": job["id"], "turn": 0}, "input": case["turns"][0]["user"],
                "reply": "You probably live on Imaginary Street.", "memories": [], "seconds": 1.0}
    result = evidence.seal(scoring.evaluate(job, [{"event": "turn", "payload": observed}], None))
    result["model"] = "apple"
    return job, result


def rubric_review(receipt):
    turn = receipt["turns"][0]
    return {"model": "apple", "job": receipt["job"], "turn": 0,
            "responseHash": evidence.response_hash(turn), "evidenceHash": evidence.review_hash(turn),
            "verdict": "fail", "note": "Invents personal information.",
            "reviewer": "test-reviewer", "scope": "rubric"}


def prepare_run(path, cases):
    jobs = corpus.jobs(cases, 1)
    configuration = {"schema": 2, "cases": cases, "corpusHash": corpus.digest(cases),
                     "models": ["apple"], "repeats": 1,
                     "jobs": [{"id": job["id"], "profile": job["profile"]} for job in jobs]}
    initialize(path, configuration)
    return configuration


class ChatBenchmarkAuditTests(unittest.TestCase):
    def test_retrieval_fixture_must_keep_sources_out_of_initial_prompt(self):
        rule = {"kind": "initial_context_omits", "values": ["The answer is violet"]}
        initial = {"instructions": "Answer from evidence", "messages": [{"content": "What is the answer?"}]}
        retrieved = {"instructions": "Answer from evidence", "messages": [{"content": "The answer is violet"}]}
        turn = {"reply": "Violet", "requests": [initial, retrieved]}
        self.assertTrue(scoring.check_rule(rule, turn, [])["passed"])
        turn['requests'][0] = retrieved
        self.assertFalse(scoring.check_rule(rule, turn, [])["passed"])
        turn['requests'][0] = {"instructions": "The answer is violet", "messages": []}
        self.assertFalse(scoring.check_rule(rule, turn, [])["passed"])
        turn['requests'] = []
        self.assertFalse(scoring.check_rule(rule, turn, [])["passed"])

    def test_memory_absence_requires_an_actual_persisted_snapshot(self):
        rule = {"kind": "memory_absent", "values": ["secret"]}
        self.assertFalse(scoring.check_rule(rule, {"reply": "Not saved"}, [])["passed"])
        self.assertTrue(scoring.check_rule(rule, {"reply": "Not saved", "memories": []}, [])["passed"])

    def test_manual_pass_cannot_certify_a_contaminated_retrieval_fixture(self):
        _, receipt = receipt_for(sample_case())
        turn = receipt["turns"][0]
        turn["checks"] = [{"category": "behavior", "kind": "initial_context_omits", "passed": False}]
        review = rubric_review(receipt)
        review["verdict"] = "pass"
        with self.assertRaisesRegex(ValueError, "invalid fixture"):
            reviews.validate(review, turn)

    def test_whitespace_is_not_a_completed_reply(self):
        case = sample_case()
        case['turns'][0]['checks'] = []
        job = corpus.jobs([case], 1)[0]
        event = {"event": "turn", "payload": {"position": {"job": job['id'], "turn": 0},
                 "input": case['turns'][0]['user'], "reply": " \n\t"}}
        self.assertFalse(scoring.evaluate(job, [event], None)['passed'])

    def test_manual_pass_cannot_override_a_failed_or_empty_turn(self):
        for reply, error in (("", None), (" \n", None), ("Partial answer", "deadline")):
            with self.subTest(reply=reply, error=error):
                _, receipt = receipt_for(sample_case())
                receipt['turns'][0].update(reply=reply, error=error)
                review = rubric_review(receipt)
                review['verdict'] = 'pass'
                with self.assertRaisesRegex(ValueError, 'failed or empty turn'):
                    reviews.summarize([review], {'apple': [receipt]})

    def test_case_failure_cannot_be_overridden_by_successful_turn_reviews(self):
        _, receipt = receipt_for(sample_case())
        receipt['error'] = 'Worker failed before its completion receipt'
        review = rubric_review(receipt)
        review['verdict'] = 'pass'
        result = reviews.summarize([review], {'apple': [receipt]})['apple']
        self.assertEqual(result['rubricCases'], {'pass': 0, 'fail': 1, 'pending': 0})

    def test_export_refreshes_reviews_and_audit_rejects_inflated_review_scores(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            case = sample_case()
            prepare_run(path, [case])
            job, receipt = receipt_for(case)
            write_json(path / 'apple/cases' / f"{job['id']}.json", receipt)
            report.generate(path)
            # Review arrives after the cached summary was written.
            write_json(path / 'reviews.json', [rubric_review(receipt)])
            destination = path / 'published.json.gz'
            archive.export(path, destination)
            checked = audit.verify(destination)['models']['apple']
            self.assertEqual(checked['reviews']['rubricCases']['fail'], 1)
            self.assertTrue(checked['publishedReviewSummaryVerified'])
            changed = audit.read_document(destination)
            changed['summary']['models']['apple']['semanticReviews']['rubricCases']['pass'] = 1
            write_json(path / 'altered.json', changed)
            with self.assertRaisesRegex(ValueError, 'review scores do not reproduce'):
                audit.verify(path / 'altered.json')

    def test_scheduling_preserves_the_full_comparison_and_order(self):
        planned = ["small", "large", "control"]
        self.assertEqual(scheduled_models(planned, ["control", "small"]), ["small", "control"])
        self.assertEqual(planned, ["small", "large", "control"])
        for invalid in ([], ["unknown"], ["small", "small"]):
            with self.assertRaises(ValueError):
                scheduled_models(planned, invalid)

    def test_incremental_history_crosses_worker_boundary_without_gold(self):
        case = sample_case()
        case["historyBatches"] = [[{"role": "user", "text": "Our code changed to amber-61."}]]
        case = corpus.validate(case)
        job = corpus.worker_job(corpus.jobs([case], 1)[0])
        self.assertEqual(job["scenario"]["historyBatches"], case["historyBatches"])
        self.assertNotIn("rubric", json.dumps(job))
        case["historyBatches"].append([])
        with self.assertRaises(ValueError):
            corpus.validate(case)

    def test_checkpoint_compaction_bound_requires_actual_measurement(self):
        rule = {"kind": "compaction_calls_at_most", "values": ["1"]}
        for count, expected in ((None, False), (0, True), (1, True), (2, False)):
            with self.subTest(count=count):
                turn = {"reply": "A reply", "compactionCalls": count}
                self.assertEqual(scoring.check_rule(rule, turn, [])["passed"], expected)

    def test_published_evidence_and_primary_metrics_reproduce(self):
        directory = ROOT / "docs/reports/data"
        result = audit.verify(directory / "local-chat-models-2026-11-01.json.gz",
                              directory / "local-chat-models-2026-11-01.corpus.json.gz")
        self.assertEqual(len(result["models"]), 7)
        self.assertEqual(sum(model["observedTurns"] for model in result["models"].values()), 735)
        for model in result["models"].values():
            self.assertEqual(model["completedCases"], model["plannedCases"])
            self.assertGreater(len(model["contextAnswerLeakage"]), 0)

    def test_full_rubric_review_can_fail_an_automated_false_pass(self):
        _, receipt = receipt_for(sample_case())
        self.assertTrue(receipt["passed"])
        results = {"apple": [receipt]}
        unreviewed = reviews.summarize([], results)["apple"]
        self.assertEqual(unreviewed["rubricCases"], {"pass": 0, "fail": 0, "pending": 1})
        reviewed = reviews.summarize([rubric_review(receipt)], results)["apple"]
        self.assertEqual(reviewed["rubricCases"], {"pass": 0, "fail": 1, "pending": 0})

    def test_reviews_bind_to_input_calls_memory_and_rubric_even_when_reply_matches(self):
        _, receipt = receipt_for(sample_case())
        review = rubric_review(receipt)
        for field, value in {"input": "A changed question", "calls": [{"name": "save_memory"}],
                             "memories": [{"key": "name", "value": "wrong"}], "rubric": "Different task"}.items():
            changed = copy.deepcopy(receipt)
            changed["turns"][0][field] = value
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, "outdated task evidence"):
                reviews.summarize([review], {"apple": [changed]})

    def test_legacy_content_reviews_do_not_certify_the_full_rubric(self):
        _, receipt = receipt_for(sample_case())
        review = rubric_review(receipt)
        del review["evidenceHash"]
        review.update(scope="content only", verdict="pass")
        result = reviews.summarize([review], {"apple": [receipt]})["apple"]
        self.assertEqual(result["legacyReplyOnlyReviews"], 1)
        self.assertEqual(result["primaryRubricReviewedTurns"], 0)
        self.assertEqual(result["rubricCases"]["pending"], 1)

    def test_answer_in_recent_messages_cannot_prove_summary_retention(self):
        rule = {"kind": "retained_context_omits", "values": ["violet-42"]}
        turn = {"reply": "violet-42", "requests": [{"instructions": "Summary: violet-42",
                "messages": [{"role": "user", "content": "The release code is violet-42."}]}]}
        self.assertFalse(scoring.check_rule(rule, turn, [])["passed"])
        turn["requests"][0]["messages"][0]["content"] = "What is the release code?"
        self.assertTrue(scoring.check_rule(rule, turn, [])["passed"])
        del turn["requests"]
        self.assertFalse(scoring.check_rule(rule, turn, [])["passed"])

    def test_order_is_reproducible_without_changing_case_membership(self):
        cases = [sample_case(f"sample-{index}") for index in range(8)]
        first = corpus.jobs(cases, 3, 17)
        self.assertEqual(first, corpus.jobs(cases, 3, 17))
        self.assertNotEqual(first, corpus.jobs(cases, 3, 18))
        self.assertEqual({job["id"] for job in first}, {job["id"] for job in corpus.jobs(cases, 3)})

    def test_missing_cases_remain_in_the_planned_denominator(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            cases = [sample_case(), sample_case("second-case")]
            prepare_run(path, cases)
            job, receipt = receipt_for(cases[0])
            write_json(path / "apple/cases" / f"{job['id']}.json", receipt)
            result = report.generate(path)["models"]["apple"]
            self.assertEqual(result["pendingPrimaryCases"], 1)
            self.assertIn("| apple | System-managed | 1/2 | 1/2 |", (path / "report.md").read_text())

    def test_release_date_comes_from_frozen_run_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            case = sample_case()
            configuration = prepare_run(path, [case])
            configuration["models"] = ["test-model"]
            release = {"date": "2026-08-04", "sourceURL": "https://example.org/original-release"}
            configuration["modelReleases"] = {"test-model": release}
            write_json(path / "run.json", configuration)
            job, receipt = receipt_for(case)
            receipt["model"] = "test-model"
            write_json(path / "test-model/cases" / f"{job['id']}.json", receipt)
            result = report.generate(path)["models"]["test-model"]
            self.assertEqual(result["release"], release)
            self.assertEqual(result["primary"]["passed"], 1)
            self.assertIn("| test-model | 2026-08-04 | 1/1 |", (path / "report.md").read_text())
            configuration.pop("modelReleases")
            write_json(path / "run.json", configuration)
            report.generate(path)
            self.assertIn("| test-model | Not recorded |", (path / "report.md").read_text())

    def test_receipt_loading_rejects_extra_files_and_modified_checks(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            case = sample_case()
            configuration = prepare_run(path, [case])
            job, receipt = receipt_for(case)
            destination = path / "apple/cases" / f"{job['id']}.json"
            write_json(destination, receipt)
            self.assertEqual(len(receipts.load(path, configuration)["apple"]), 1)
            extra = destination.with_name("duplicate.json")
            write_json(extra, receipt)
            with self.assertRaises(ValueError):
                receipts.load(path, configuration)
            extra.unlink()
            receipt["turns"][0]["checks"][0]["passed"] = False
            write_json(destination, receipt)
            with self.assertRaisesRegex(ValueError, "do not reproduce"):
                receipts.load(path, configuration)

    def test_resume_rejects_altered_receipt_instead_of_skipping_it(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            case = sample_case()
            job, receipt = receipt_for(case)
            receipt["turns"][0]["reply"] = "Changed after evaluation"
            write_json(root / "apple/cases" / f"{job['id']}.json", receipt)
            options = SimpleNamespace(output=root, startup_timeout=1)
            with self.assertRaisesRegex(ValueError, "hash mismatch"):
                ModelBatch(options, "apple", [job], time.monotonic() + 1)

    def test_operator_interruption_leaves_an_explicit_receipt(self):
        with tempfile.TemporaryDirectory() as directory:
            options = SimpleNamespace(output=Path(directory), startup_timeout=1)
            job = corpus.jobs([sample_case()], 1)[0]
            batch = ModelBatch(options, "apple", [job], time.monotonic() + 3)
            batch.current = job
            with patch.object(batch, "_attempt", side_effect=KeyboardInterrupt), self.assertRaises(KeyboardInterrupt):
                batch.run()
            result = json.loads((options.output / "apple/cases" / f"{job['id']}.json").read_text())
            self.assertIn("operator", result["error"])
            self.assertFalse(result["passed"])
            self.assertEqual(ModelBatch(options, "apple", [job], time.monotonic() + 1).jobs, [])

    def test_kernel_changes_invalidate_resume_even_when_executable_is_unchanged(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            worker = root / "worker"
            bundle = root / "Sillies_SilliesModelStore.bundle"
            bundle.mkdir()
            (bundle / "text-models.json").write_text("{}")
            helper = root / "Helper.app/Contents/MacOS/helper"
            helper.parent.mkdir(parents=True)
            helper.write_text("unchanged executable")
            kernel = helper.parent / "kernel.metallib"
            kernel.write_text("original")
            first = {"runtimeResources": environment.runtime_resources(worker, helper)}
            initialize(root / "run", first)
            kernel.write_text("changed")
            with self.assertRaises(ValueError):
                initialize(root / "run", {"runtimeResources": environment.runtime_resources(worker, helper)})

    def test_protocol_rejects_result_without_turn_start_and_incomplete_success(self):
        job = corpus.jobs([sample_case()], 1)[0]
        position = {"job": job["id"], "turn": 0}
        invalid_events = [
            {"event": "turn", "payload": {"position": position}},
            {"event": "caseFinished", "payload": {"job": job["id"], "completedTurns": 0}},
        ]
        for invalid in invalid_events:
            with self.subTest(event=invalid["event"]), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                worker = root / "worker.py"
                events = [{"event": "caseStarted", "payload": {"id": job["id"]}}, invalid]
                worker.write_text("#!/usr/bin/env python3\nimport json\n"
                                  "print(json.dumps({'event':'model','payload':{'id':'apple'}}),flush=True)\ninput()\n"
                                  f"for event in {events!r}: print(json.dumps(event),flush=True)\n")
                worker.chmod(0o755)
                options = SimpleNamespace(output=root / "out", worker=worker, helper=worker, models_root=root,
                                          startup_timeout=1, case_timeout=1, turn_timeout=1)
                ModelBatch(options, "apple", [job], time.monotonic() + 3).run()
                result = json.loads((options.output / "apple/cases" / f"{job['id']}.json").read_text())
                self.assertFalse(result["passed"])
                self.assertIn("protocol failed", result["error"])


if __name__ == "__main__":
    unittest.main()
