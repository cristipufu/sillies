"""Catalog failures must be caught before native formatting can crash the app."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from localization_catalog import metadata_problems, plural_rules
from localization_compiler import compile_strings, extraction_arguments, prepare_frontend
from localization_formats import placeholder_problem
from localization_validation import Coverage, catalog_problems

spec = importlib.util.spec_from_file_location("sillies_localize", ROOT / "scripts/localize.py")
localize = importlib.util.module_from_spec(spec)
spec.loader.exec_module(localize)


class LocalizationTests(unittest.TestCase):
    def test_extraction_uses_its_own_build_cache_and_keeps_the_build_log(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            workspace = root / "localization"
            workspace.mkdir()
            emitted = workspace / "module-strings/Example/Label.stringsdata"

            def build(command, *, cwd, stdout, stderr):
                self.assertEqual(cwd, root)
                self.assertEqual(command[command.index("--scratch-path") + 1], str(workspace / "build"))
                self.assertEqual(stderr, subprocess.STDOUT)
                stdout.write("Compiler build output\n")
                emitted.parent.mkdir(parents=True)
                emitted.write_text("{}")
                return subprocess.CompletedProcess(command, 0)

            with patch("localization_compiler.prepare_frontend", return_value=workspace / "swift-frontend"), \
                 patch("localization_compiler.subprocess.check_output", return_value="/toolchain/resources"), \
                 patch("localization_compiler.subprocess.run", side_effect=build):
                self.assertEqual(compile_strings(root, workspace), [emitted])
            self.assertEqual((workspace / "build.log").read_text(), "Compiler build output\n")
            self.assertFalse((root / ".build").exists())

    def test_compiler_preserves_same_named_sources_in_both_modules(self):
        with tempfile.TemporaryDirectory(prefix="sillies extraction ") as folder:
            root = Path(folder)
            frontend = prepare_frontend(root)
            output = root / "strings"
            for module in ("AppFixture", "DependencyFixture"):
                sources = root / module
                sources.mkdir()
                source = sources / "Duplicate.swift"
                message = module + " message"
                source.write_text('import Foundation\nlet message = String(localized: "' + message + '")\n')
                subprocess.run(["xcrun", "swiftc", "-c", "-module-name", module,
                                "-emit-localized-strings", "-emit-localized-strings-path", str(output),
                                "-driver-use-frontend-path", str(frontend),
                                "-o", str(sources / "Duplicate.o"), str(source)],
                               capture_output=True, text=True, check=True, timeout=30)
            for module in ("AppFixture", "DependencyFixture"):
                data = json.loads((output / module / "Duplicate.stringsdata").read_text())
                self.assertEqual(data["tables"]["Localizable"][0]["key"], module + " message")
            self.assertFalse((output / "Duplicate.stringsdata").exists())

    def test_extraction_keeps_same_named_dependency_files_in_separate_modules(self):
        arguments = ["-module-name", "SilliesAudio", "-emit-localized-strings-path", "/output"]
        self.assertEqual(extraction_arguments(arguments)[-1], "/output/SilliesAudio")
        arguments[1] = "WhisperKit"
        self.assertEqual(extraction_arguments(arguments)[-1], "/output/WhisperKit")
        self.assertEqual(arguments[-1], "/output")
        self.assertEqual(extraction_arguments(["-version"]), ["-version"])
        arguments[1] = "../escape"
        with self.assertRaises(ValueError):
            extraction_arguments(arguments)

    def test_native_argument_types_and_numbered_reordering(self):
        source = "%@ has %lld items (%.2lf GB)"
        self.assertIsNone(placeholder_problem(source, "%2$lld: %1$@ (%3$.2lf GB)"))
        for text in ["%@ has %d items (%.2lf GB)", "%@ has %lld items", "%n", "%s", "%p", "%*d",
                     "%1$@ %lld %.2lf", "%4$@ %2$lld %3$lf", "%1$@ %2$@ %3$lf"]:
            with self.subTest(text=text):
                self.assertIsNotNone(placeholder_problem(source, text))

    def test_literal_percent_and_argument_reuse(self):
        self.assertIsNone(placeholder_problem("%lld%% downloaded", "%lld%% geladen"))
        self.assertIsNone(placeholder_problem("%lld%% downloaded", "%lld%% staženo"))
        self.assertIsNone(placeholder_problem("%@", "%1$@ · %1$@"))
        self.assertIsNone(placeholder_problem("100%", "100%"))

    def test_translations_cannot_introduce_unbounded_or_malformed_formats(self):
        for text in ["%1000000000@", "%1$1000000000@", "%l@", "%1$q"]:
            with self.subTest(text=text):
                self.assertIsNotNone(placeholder_problem("%@", text))
        self.assertIsNotNone(placeholder_problem("%.2lf", "%.999999999lf"))

    def test_shipped_catalogs_include_stratas_language_set_and_are_complete(self):
        expected = {"cs", "da", "de", "en", "es", "fr", "hu", "it", "ja", "ko", "nb", "nl",
                    "pl", "pt-BR", "pt-PT", "ro", "ru", "sv", "tr", "uk", "zh-Hans", "zh-Hant"}
        self.assertTrue(expected.issubset({p.stem for p in localize.FOLDER.glob("*.json")}))
        with contextlib.redirect_stdout(io.StringIO()):
            localize.check("--all", coverage=Coverage.COMPLETE)

    def test_duplicate_keys_fail(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "en.json"
            path.write_text('{"strings":{"Save":"Save","Save":"Other"}}')
            with self.assertRaises(ValueError):
                localize.load(path)

    def test_new_language_needs_no_registry_edit(self):
        data = {"code": "cy", "language": "Cymraeg", "english": "Welsh", "plurals": ["zero", "one", "two", "few", "many", "other"]}
        self.assertEqual(metadata_problems(data, "cy"), [])
        self.assertEqual(plural_rules("cy", data)[0], data["plurals"])
        self.assertTrue(metadata_problems(data, "../cy"))

    def test_malformed_metadata_is_a_diagnostic_not_a_validator_crash(self):
        english = {"Open": "Open"}
        for plurals in [42, "other", ["one", {}], [], ["not-a-category", "other"]]:
            data = {"code": "cy", "language": "Cymraeg", "english": "Welsh",
                    "plurals": plurals, "strings": english}
            with self.subTest(plurals=plurals):
                self.assertTrue(catalog_problems(data, "cy", english, Coverage.COMPLETE))

    def test_validation_is_pure_and_explicit_about_coverage(self):
        english = {"Open": "Open", "%lld items": {"one": "%lld item", "other": "%lld items"}}
        data = {"code": "fr", "language": "Français", "english": "French", "strings": {"Open": ""}}
        original = json.dumps([english, data], sort_keys=True)
        self.assertEqual(catalog_problems(data, "fr", english, Coverage.PRESENT), [])
        problems = catalog_problems(data, "fr", english, Coverage.COMPLETE)
        self.assertEqual(len(problems), 2)
        self.assertEqual(json.dumps([english, data], sort_keys=True), original)
        data["strings"]["%lld items"] = {"one": "%lld élément"}
        self.assertTrue(catalog_problems(data, "fr", english, Coverage.PRESENT))

    def test_packaging_discovers_languages_and_emits_native_plurals(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            catalogs = root / "Localization"
            catalogs.mkdir()
            source = {"language": "English", "english": "English", "code": "en", "maintainers": [], "strings": {
                "%lld items": {"one": "%lld item", "other": "%lld items"},
                "Open": "Open", "infoplist.NSMicrophoneUsageDescription": "Record your voice."}}
            french = {**source, "language": "Français", "english": "French", "code": "fr", "strings": {
                "%lld items": {"one": "%lld élément", "other": "%lld éléments"},
                "Open": "Ouvrir", "infoplist.NSMicrophoneUsageDescription": "Enregistrer votre voix."}}
            for data in [source, french]:
                (catalogs / (data["code"] + ".json")).write_text(json.dumps(data))
            with patch.object(localize, "FOLDER", catalogs), patch.object(localize, "SOURCE", catalogs / "en.json"), contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                localize.build(root / "out")
                metadata = json.loads((root / "out/Languages.json").read_text())
                self.assertEqual({item["code"] for item in metadata}, {"en", "fr"})
                self.assertIn("Ouvrir", (root / "out/fr.lproj/Localizable.strings").read_text())
                self.assertIn("Enregistrer", (root / "out/fr.lproj/InfoPlist.strings").read_text())
                plural = plistlib.loads((root / "out/fr.lproj/Localizable.stringsdict").read_bytes())
                self.assertEqual(plural["%lld items"]["n"]["NSStringFormatValueTypeKey"], "lld")
                self.assertEqual(plural["%lld items"]["n"]["one"], "%1$lld élément")
                french["strings"]["Open"] = ""
                (catalogs / "fr.json").write_text(json.dumps(french))
                with self.assertRaises(SystemExit):
                    localize.build(root / "unsafe")


if __name__ == "__main__":
    unittest.main()
