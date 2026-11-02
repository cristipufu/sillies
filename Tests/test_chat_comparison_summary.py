"""Published comparisons must preserve failures, review coverage and matched conditions."""
import copy
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

path = Path(__file__).resolve().parents[1] / "scripts/summarize-chat-benchmarks.py"
spec = importlib.util.spec_from_file_location("chat_comparison_summary", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
from evaluation import archive, report
from test_chat_benchmark_audit import prepare_run, receipt_for, rubric_review, sample_case


def receipt(passed=True, repeat=1):
    return {"model": "model", "job": f"case--app--r{repeat}", "case": "case", "group": "knowledge",
            "profile": "app", "repeat": repeat, "passed": passed, "turns": [{"reply": "Paris", "checks": []}]}


class ComparisonSummaryTests(unittest.TestCase):
    def test_published_archive_reproduces_directory_measurements_and_rejects_tampering(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary) / "run"
            prepare_run(directory, [sample_case()])
            _, case = receipt_for(sample_case())
            destination = directory / "apple" / "cases" / f"{case['job']}.json"
            destination.parent.mkdir(parents=True)
            destination.write_text(json.dumps(case))
            (directory / "reviews.json").write_text(json.dumps([rubric_review(case)]))
            report.generate(directory)
            published = Path(temporary) / "published.json.gz"
            archive.export(directory, published)
            configuration, original = module.complete_run(directory)
            archived_configuration, archived = module.complete_run(published)
            self.assertEqual(configuration, archived_configuration)
            self.assertEqual(module.primary_measurements(original, module.review_index(directory, original)),
                             module.primary_measurements(archived, module.review_index(published, archived)))
            document = module.audit.read_document(published)
            document["models"]["apple"]["cases"][0]["turns"][0]["reply"] = "An altered response"
            corrupted = Path(temporary) / "corrupted.json"
            corrupted.write_text(json.dumps(document))
            with self.assertRaises(ValueError):
                module.complete_run(corrupted)

    def test_incomplete_published_run_cannot_become_a_comparison(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary) / "run"
            prepare_run(directory, [sample_case()])
            report.generate(directory)
            published = Path(temporary) / "incomplete.json.gz"
            archive.export(directory, published)
            with self.assertRaisesRegex(ValueError, "Complete every planned case"):
                module.complete_run(published)

    def test_no_review_or_uncertain_review_cannot_become_a_score(self):
        case = receipt()
        with self.assertRaises(ValueError):
            module.reviewed_case(case, {})
        judgment = {"scope": "rubric", "evidenceHash": "hash", "verdict": "uncertain"}
        with self.assertRaises(ValueError):
            module.reviewed_case(case, {("model", case["job"], 0): judgment})

    def test_error_remains_failed_even_with_a_passing_judgment(self):
        judgment = {"scope": "rubric", "evidenceHash": "hash", "verdict": "pass"}
        for level in ("case", "turn"):
            case = receipt()
            target = case if level == "case" else case["turns"][0]
            target["error"] = "Timeout"
            self.assertFalse(module.reviewed_case(case, {("model", case["job"], 0): judgment}))

    def test_repeats_keep_failed_passes_and_case_instability(self):
        failed = receipt(False)
        failed["turns"] = [{"error": "Incomplete response", "checks": []}]
        result = module.repeat_measurements({"model": [receipt()]},
                                            {"model": [failed, receipt(True, 2)]})["model"]
        self.assertEqual(result["automatedPasses"], [1, 0, 1])
        self.assertEqual(result["errorTurns"], [0, 1, 0])
        self.assertEqual(result["allPassesSucceeded"], 0)
        self.assertEqual(result["changedOutcome"], 1)

    def test_repeat_timings_keep_passes_separate_and_exclude_error_samples(self):
        primary, failed, repeated = receipt(), receipt(False), receipt(True, 2)
        for case, seconds in ((primary, 2), (failed, 90), (repeated, 4)):
            case["turns"][0].update(checks=[], firstTextSeconds=seconds, seconds=seconds + 1)
        failed["turns"][0]["error"] = "Timeout"
        timings = module.repeat_timings({"model": [primary]}, {"model": [failed, repeated]})["model"]
        self.assertEqual([item["sampleCounts"]["firstTextTurns"] for item in timings], [1, 0, 1])
        self.assertEqual([item["automatic"]["firstTextP50"] for item in timings], [2, None, 4])

    def test_failed_context_turn_without_a_reply_remains_reportable(self):
        case = receipt(False)
        case.update(group="context")
        case["turns"] = [{"error": "Incomplete response", "checks": [], "calls": []}]
        review = {"scope": "rubric", "evidenceHash": "hash", "verdict": "fail"}
        result = module.primary_measurements({"model": [case]}, {("model", case["job"], 0): review})["model"]
        self.assertEqual(result["score"], 0)
        self.assertEqual(result["automatic"]["errors"], 1)
        self.assertIsNone(result["compaction"][0]["reply"])
        self.assertEqual(result["compaction"][0]["error"], "Incomplete response")

    def test_repeat_cannot_hide_a_missing_scenario(self):
        repeated = [receipt(), receipt(True, 2)]
        repeated[1]["case"] = "different"
        with self.assertRaises(ValueError):
            module.repeat_measurements({"model": [receipt()]}, {"model": repeated})

    def test_tool_sweep_does_not_mix_unrelated_cases_into_five_tool_denominator(self):
        cases = []
        for group, profile in (("tool-scaling", "app"), ("tool-scaling", "expanded8"), ("knowledge", "app")):
            case = receipt()
            case.update(group=group, profile=profile)
            case["turns"][0]["checks"] = []
            cases.append(case)
        result = module.tool_scaling_measurements(cases)
        self.assertEqual(result["app"]["cases"], 1)
        self.assertEqual(result["expanded8"]["cases"], 1)

    def test_repeated_conditions_and_fixtures_must_match(self):
        configuration = {key: "same" for key in (
            "sourceCommit", "evaluatorHash", "workerHash", "helperHash", "catalogHash",
            "runtimeResources", "machine", "turnTimeout", "caseTimeout", "startupTimeout")}
        configuration.update(models=["model"], cases=[{"id": "case", "turns": ["Original question"]}])
        module.matched_extension(configuration, copy.deepcopy(configuration))
        for key in ("machine", "helperHash", "models", "cases", "modelReleases"):
            changed = copy.deepcopy(configuration)
            changed[key] = [{"id": "case", "turns": ["Changed question"]}] if key == "cases" else "changed"
            with self.assertRaises(ValueError):
                module.matched_extension(configuration, changed)

    def test_changed_or_missing_installed_revision_cannot_be_called_a_repeat(self):
        metadata = {"model": {"revision": "first", "contextTokens": 4096}}
        module.matched_model_metadata(metadata, copy.deepcopy(metadata))
        for changed in ({"model": None}, {"model": {"revision": "second", "contextTokens": 4096}},
                        {"model": {"revision": "first", "contextTokens": 2048}}):
            with self.assertRaises(ValueError):
                module.matched_model_metadata(metadata, changed)
        with self.assertRaises(ValueError):
            module.matched_model_metadata({"model": None}, {"model": None})

    def test_exact_answer_timing_excludes_preambles_errors_and_wrong_answers(self):
        case = receipt()
        case["turns"][0].update(checks=[{"kind": "reply_equals", "passed": True}],
                                textEmissions=[{"seconds": 1, "text": "\n"}, {"seconds": 2, "text": "Paris"}])
        judgments = {("model", case["job"], 0): {"verdict": "pass"}}
        self.assertEqual(module.correct_short_answer_times([case], judgments), {"count": 1, "p50": 2, "p95": 2})
        for mutation in ({"error": "Timeout"}, {"checks": []}, {"checks": [{"kind": "reply_equals", "passed": False}]}):
            changed = copy.deepcopy(case)
            changed["turns"][0].update(mutation)
            self.assertEqual(module.correct_short_answer_times([changed], judgments)["count"], 0)

    def test_executed_save_is_counted_even_when_the_answer_claims_privacy(self):
        case = receipt()
        case["turns"][0].update(reply="I won't save it.", checks=[{"kind": "no_writes"}],
                                calls=[{"name": "save_memory"}])
        self.assertEqual(module.memory_write_attempts([case]), {"noWriteTurns": 1, "turnsWithUnwantedSaveCall": 1})

    def test_timing_counts_do_not_turn_missing_or_failed_measurements_into_samples(self):
        case = receipt()
        case["turns"] = [{"firstTextSeconds": 0, "seconds": 1}, {"seconds": 2},
                         {"firstTextSeconds": 3, "seconds": 4, "error": "Failed"}, {}]
        self.assertEqual(module.timing_counts([case]), {"firstTextTurns": 1, "completedTimedTurns": 2})

    def test_memory_change_score_excludes_recall_and_keeps_conflicting_old_values(self):
        case = receipt()
        case["turns"] = [
            {"checks": [{"kind": "memory_contains", "passed": True}, {"kind": "memory_absent", "passed": False}]},
            {"checks": [{"kind": "memory_contains", "passed": True}, {"kind": "no_writes", "passed": True}]},
            {"checks": [{"kind": "memory_contains", "passed": True}]},
        ]
        judgments = {("model", case["job"], index): {"verdict": "pass"} for index in range(3)}
        self.assertEqual(module.memory_state_changes([case], judgments), {"requiredTurns": 2, "reviewedPasses": 1})
