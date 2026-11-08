"""The checked runner must reject an early successful exit and accept explicit skips."""
import json
import os
import re
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from checked_test_process import TestProcess
from test_suites import test_batches
from test_evidence import (IncompleteTestRun, selected_tests, swift_inventory, swift_test_name,
                           verify_swift_run, verify_xctest_run, xctest_inventory)


def event(kind, **fields):
    return dict(version=0, kind="event", payload=dict(kind=kind, **fields))


class TestEvidenceTests(unittest.TestCase):
    def stream(self, records):
        root = tempfile.TemporaryDirectory()
        self.addCleanup(root.cleanup)
        path = Path(root.name) / "events.jsonl"
        path.write_text("".join(json.dumps(record) + "\n" for record in records))
        return path

    def test_requires_run_end_and_receipt_for_every_selected_test(self):
        started = event("runStarted")
        ended = event("runEnded")
        completed = event("testEnded", testID="a")
        for records in [[started], [started, ended], [started, completed],
                        [started, completed, completed, ended]]:
            with self.subTest(records=records), self.assertRaises(IncompleteTestRun):
                verify_swift_run(self.stream(records), {"a"})
        self.assertEqual(verify_swift_run(self.stream([started, completed, ended]), {"a"}), 1)

    def test_parameterized_cases_and_explicit_skips(self):
        records = [event("runStarted"), event("testStarted", testID="a"),
                   event("testCaseEnded", testID="a"), event("testCaseEnded", testID="a"),
                   event("testEnded", testID="a"), event("testSkipped", testID="b"), event("runEnded")]
        self.assertEqual(verify_swift_run(self.stream(records), {"a", "b"}), 2)
        with self.assertRaises(IncompleteTestRun):
            verify_swift_run(self.stream(records[:-1]), {"a", "b"})

    def test_failure_receipts_cannot_turn_a_zero_exit_into_success(self):
        records = [event("runStarted"), event("testEnded", testID="a",
                   messages=[dict(symbol="fail", text="failed")]), event("runEnded")]
        with self.assertRaises(IncompleteTestRun):
            verify_swift_run(self.stream(records), {"a"})

    def test_discovery_preserves_source_identity_and_filters_use_runtime_names(self):
        identifier = "Tests.Suite/example(value:)/Example.swift:10:2"
        records = [dict(version=0, kind="test", payload=dict(id=identifier, kind="function")),
                   dict(version=0, kind="test", payload=dict(id="Tests.Suite", kind="suite"))]
        self.assertEqual(swift_inventory(self.stream(records)), {identifier})
        self.assertEqual(selected_tests({identifier}, ["example"], [], swift_test_name), {identifier})
        self.assertEqual(selected_tests({identifier}, [], ["Suite"], swift_test_name), set())
        self.assertEqual(selected_tests({identifier}, ["Example.swift"], [], swift_test_name), set())

    def test_runtime_cannot_silently_expand_the_selected_set(self):
        records = [dict(version=0, kind="test", payload=dict(kind="function", id="unexpected")),
                   event("runStarted"), event("testEnded", testID="wanted"), event("runEnded")]
        with self.assertRaises(IncompleteTestRun):
            verify_swift_run(self.stream(records), {"wanted"})

    def test_unknown_or_truncated_event_formats_fail(self):
        with self.assertRaises(IncompleteTestRun):
            swift_inventory(self.stream([dict(version=99, kind="test")]))
        path = self.stream([])
        path.write_text('{"version":0,')
        with self.assertRaises(ValueError):
            verify_swift_run(path, {"a"})

    def test_xctest_discovery_completion_and_skips(self):
        inventory = dict(name="All Tests", tests=[dict(name="Tests.Suite", tests=[dict(name="testA")])])
        self.assertEqual(xctest_inventory(inventory), {"Tests.Suite/testA"})
        for state in ["passed", "skipped"]:
            log = f"Test Case '-[Tests.Suite testA]' {state} (0.001 seconds).\nTest Suite 'Selected tests' passed\n"
            self.assertEqual(verify_xctest_run(log, {"Tests.Suite/testA"}), 1)
            with self.assertRaises(IncompleteTestRun):
                verify_xctest_run(log.splitlines()[0], {"Tests.Suite/testA"})
        with self.assertRaises(IncompleteTestRun):
            verify_xctest_run("Test Suite 'Selected tests' passed", {"Tests.Suite/testA"})

    def test_successful_process_without_receipts_is_rejected(self):
        path = self.stream([])
        TestProcess(5, dict(os.environ)).run([sys.executable, "-c", "pass"], path.with_suffix(".log"))
        with self.assertRaises(IncompleteTestRun):
            verify_swift_run(path, {"a"})

    def test_process_timeout_is_bounded(self):
        path = self.stream([])
        with self.assertRaises(TimeoutError):
            TestProcess(0.1, dict(os.environ)).run(
                [sys.executable, "-c", "import time; time.sleep(10)"], path.with_suffix(".log"))

    def test_default_workflow_batches_cover_every_bundle_and_test_once(self):
        bundles = [Path(name + ".xctest") for name in [
            "SilliesAppTests", "SilliesAudioTests", "SilliesPersistenceTests",
            "SilliesCoreTests", "SilliesNewFeatureTests", "FutureLibraryTests"]]
        batches = test_batches(bundles)
        self.assertEqual(len(batches), 4)
        self.assertCountEqual([bundle for batch in batches for bundle in batch], bundles)
        for bundle in bundles[:3]:
            self.assertIn([bundle], batches)
        self.assertEqual(test_batches([]), [])

    def test_race_workflow_batches_keep_native_and_voice_checks_disjoint(self):
        script = Path(__file__).resolve().parents[1] / "scripts/test-races.sh"
        text = script.read_text()
        variables = dict(re.findall(r"^([a-z_]+)=['\"]([^'\"]+)['\"]", text, re.MULTILINE))

        def expanded(value):
            return re.sub(r"\$(\w+)", lambda match: expanded(variables[match[1]]), value)

        batch = text.split("for race_skip in", 1)[1].split("; do", 1)[0]
        patterns = [expanded(value) for value in re.findall(r"['\"]([^'\"]+)['\"]", batch)]
        self.assertEqual(len(patterns), 3)
        bundles = ["App", "Audio", "Core", "Persistence", "Reasoning", "Search", "Speech",
                   "Chat", "TTS", "TextModels", "VoicePlayback", "Writing", "NewFeature"]
        for bundle in [*("Sillies" + name + "Tests" for name in bundles), "FutureLibraryTests"]:
            selected = [pattern for pattern in patterns if not re.fullmatch(pattern, bundle)]
            self.assertEqual(len(selected), 1, bundle)
            identifier = bundle + ".example()"
            self.assertEqual(selected_tests({identifier}, [], selected), {identifier})
            self.assertEqual(sum(not re.search(pattern, identifier) for pattern in patterns), 1)
        self.assertTrue(all(re.fullmatch(pattern, "SilliesFishSpeechTests") for pattern in patterns))
        # The separate PCM matrices must not also run in a general batch.
        for name in ["voiceConversationResamplesDeviceQuantaWithoutSelfInterruption",
                     "voiceConversationRejectsEchoAcrossAcousticDelays"]:
            self.assertTrue(all(re.search(pattern, "SilliesAudioTests." + name) for pattern in patterns))


if __name__ == "__main__":
    unittest.main()
