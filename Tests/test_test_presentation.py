"""Native tests cannot silently leak into headless runs or disappear from GUI coverage."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from test_evidence import IncompleteTestRun
from test_presentation import TestPresentation


class TestPresentationTests(unittest.TestCase):
    headless = "SilliesAppTests.layout()/Example.swift:10:2"
    visible = "SilliesAppTests.window(mode:)/Example.swift:20:2"

    def policy(self, files):
        root = tempfile.TemporaryDirectory()
        self.addCleanup(root.cleanup)
        path = Path(root.name) / "modes.json"
        path.write_text(json.dumps(files))
        return TestPresentation(path)

    def test_partition_preserves_every_test_exactly_once(self):
        policy = self.policy({"Example.swift": {"default": "headless", "tests": {"window(mode:)": "gui"}}})
        groups = policy.partition({self.headless, self.visible})
        self.assertEqual(groups, {"headless": {self.headless}, "gui": {self.visible}})

    def test_new_native_sources_require_explicit_classification(self):
        with self.assertRaises(IncompleteTestRun):
            self.policy({}).partition({self.headless})

    def test_deleted_or_renamed_tests_cannot_leave_stale_exclusions(self):
        for files in [{"Old.swift": {"default": "gui"}},
                      {"Example.swift": {"default": "headless", "tests": {"oldWindow()": "gui"}}}]:
            with self.subTest(files=files), self.assertRaises(IncompleteTestRun):
                self.policy(files).partition({self.headless})

    def test_unknown_modes_cannot_silently_drop_tests(self):
        with self.assertRaises(IncompleteTestRun):
            self.policy({"Example.swift": {"default": "skip"}}).partition({self.headless})

    def test_gui_file_can_keep_pure_cases_in_headless_checks(self):
        policy = self.policy({"Example.swift": {"default": "gui", "tests": {"layout()": "headless"}}})
        self.assertEqual(policy.partition({self.headless, self.visible}),
                         {"headless": {self.headless}, "gui": {self.visible}})


if __name__ == "__main__":
    unittest.main()
