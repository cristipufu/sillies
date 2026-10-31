"""Packaging regressions for the missing-Sparkle launch crash; no app data or UI."""

from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/embed-sparkle.sh"


class SparklePackagingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="sillies packaging ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.artifacts = self.root / "artifacts"
        self.app = self.root / "Sillies.app"
        self.framework = self.artifacts / "sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
        self.library = self.framework / "Versions/B/Sparkle"
        self.executable = self.app / "Contents/MacOS/Sillies"

    def embed(self):
        return subprocess.run(
            ["bash", str(SCRIPT), str(self.artifacts), str(self.app)],
            capture_output=True, text=True, timeout=10,
        )

    def test_missing_artifacts_fail_before_modifying_the_app(self):
        for existing_directory in [False, True]:
            with self.subTest(existing_directory=existing_directory):
                if existing_directory:
                    self.artifacts.mkdir()
                result = self.embed()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Cannot package Sillies", result.stderr)
                self.assertFalse(self.app.exists())

    def test_incomplete_framework_fails_before_modifying_the_app(self):
        self.library.parent.mkdir(parents=True)
        for empty_binary in [False, True]:
            with self.subTest(empty_binary=empty_binary):
                if empty_binary:
                    self.library.touch()
                result = self.embed()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("missing or incomplete", result.stderr)
                self.assertFalse(self.app.exists())

    def test_packaged_binary_launches_without_the_build_artifacts(self):
        self.library.parent.mkdir(parents=True)
        resources = self.library.parent / "Resources"
        resources.mkdir()
        (resources / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "app.sillies.sparkle-fixture",
            "CFBundleExecutable": "Sparkle",
            "CFBundlePackageType": "FMWK",
        }))
        (self.framework / "Versions/Current").symlink_to("B")
        (self.framework / "Sparkle").symlink_to("Versions/Current/Sparkle")
        (self.framework / "Resources").symlink_to("Versions/Current/Resources")
        self.executable.parent.mkdir(parents=True)
        (self.app / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "app.sillies.packaging-fixture",
            "CFBundleExecutable": "Sillies",
            "CFBundlePackageType": "APPL",
        }))
        library_source = self.root / "library.c"
        library_source.write_text("int sparkle_fixture_value(void) { return 42; }\n")
        host_source = self.root / "host.c"
        host_source.write_text(
            "extern int sparkle_fixture_value(void);\n"
            "int main(void) { return sparkle_fixture_value() == 42 ? 0 : 1; }\n"
        )
        subprocess.run(
            ["xcrun", "clang", "-dynamiclib", str(library_source),
             "-Wl,-install_name,@rpath/Sparkle.framework/Versions/B/Sparkle",
             "-o", str(self.library)],
            check=True, capture_output=True, timeout=20,
        )
        subprocess.run(
            ["xcrun", "clang", str(host_source), str(self.library),
             "-Wl,-headerpad_max_install_names", "-o", str(self.executable)],
            check=True, capture_output=True, timeout=20,
        )
        for _ in range(2):
            result = self.embed()
            self.assertEqual(result.returncode, 0, result.stderr)
        for bundle in [self.app / "Contents/Frameworks/Sparkle.framework", self.app]:
            signed = subprocess.run(
                ["codesign", "--force", "--sign", "-", str(bundle)],
                capture_output=True, text=True, timeout=10,
            )
            self.assertEqual(signed.returncode, 0, signed.stderr)
        shutil.rmtree(self.artifacts)
        launched = subprocess.run([str(self.executable)], capture_output=True, timeout=10)
        self.assertEqual(launched.returncode, 0, launched.stderr)


if __name__ == "__main__":
    unittest.main()
