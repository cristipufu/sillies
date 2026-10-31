"""Offline regressions for the attribution inventory and upstream-text preservation."""

import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/third-party-notices.py"
SPEC = importlib.util.spec_from_file_location("third_party_notices", SCRIPT)
notices = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = notices
SPEC.loader.exec_module(notices)


class ThirdPartyNoticesTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.package = notices.PackageNotices("example-sdk", "Example runtime", ("LICENSE", "NOTICE"))
        mapping = patch.dict(notices.PACKAGES, {"example-sdk": self.package}, clear=True)
        mapping.start()
        self.addCleanup(mapping.stop)
        self.pin = {
            "identity": "example-sdk",
            "location": "https://github.com/example/sdk.git",
            "state": {"revision": "immutable-commit", "version": "1.2.3"},
        }
        self.write_pins([self.pin])

    def write_pins(self, pins):
        (self.root / "Package.resolved").write_text(json.dumps({"pins": pins}))

    def test_new_dependency_requires_explicit_attribution(self):
        self.write_pins([self.pin, {**self.pin, "identity": "another-sdk"}])
        with self.assertRaisesRegex(ValueError, "another-sdk"):
            notices.resolved_packages(self.root)

    def test_removed_dependency_does_not_leave_a_false_inventory(self):
        self.write_pins([])
        with self.assertRaisesRegex(ValueError, "remove.*example-sdk"):
            notices.resolved_packages(self.root)

    def test_duplicate_resolved_identity_is_rejected(self):
        self.write_pins([self.pin, self.pin])
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            notices.resolved_packages(self.root)

    def test_missing_or_empty_upstream_notice_fails_generation(self):
        directory = self.root / ".build/checkouts/example-sdk"
        directory.mkdir(parents=True)
        (directory / "LICENSE").write_text("Copyright Example Authors\n")
        with self.assertRaises(FileNotFoundError):
            notices.package_licenses(self.root, [self.pin])
        (directory / "NOTICE").write_text(" \n")
        with self.assertRaisesRegex(ValueError, "Empty"):
            notices.package_licenses(self.root, [self.pin])

    def test_license_and_separate_notice_are_preserved(self):
        directory = self.root / ".build/checkouts/example-sdk"
        directory.mkdir(parents=True)
        license_text = "Copyright © Example Authors\nAll conditions remain unchanged."
        notice_text = "Upstream attribution:\n  Derived from another project."
        (directory / "LICENSE").write_text(license_text)
        (directory / "NOTICE").write_text(notice_text)
        output = notices.package_licenses(self.root, [self.pin])
        self.assertIn(license_text, output)
        self.assertIn(notice_text, output)
        self.assertIn("example-sdk 1.2.3", output)
        self.assertIn("https://github.com/example/sdk/tree/immutable-commit", notices.package_inventory([self.pin]))

    def test_update_replaces_the_complete_document_without_scratch_files(self):
        destination = self.root / "notices.md"
        destination.write_text("Old notices")
        notices.write_atomic(destination, "Complete replacement\n")
        self.assertEqual(destination.read_text(), "Complete replacement\n")
        self.assertEqual({p.name for p in self.root.iterdir()}, {"Package.resolved", "notices.md"})


if __name__ == "__main__":
    unittest.main()
