"""Catalog failures must be caught before native formatting can crash the app."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
spec = importlib.util.spec_from_file_location("sillies_localize", ROOT / "scripts/localize.py")
localize = importlib.util.module_from_spec(spec)
spec.loader.exec_module(localize)


class LocalizationTests(unittest.TestCase):
    def test_native_argument_types_and_numbered_reordering(self):
        source = "%@ has %lld items (%.2lf GB)"
        self.assertIsNone(localize.placeholder_problem(source, "%2$lld: %1$@ (%3$.2lf GB)"))
        for text in ["%@ has %d items (%.2lf GB)", "%@ has %lld items", "%n", "%s", "%p", "%*d",
                     "%1$@ %lld %.2lf", "%4$@ %2$lld %3$lf", "%1$@ %2$@ %3$lf"]:
            with self.subTest(text=text):
                self.assertIsNotNone(localize.placeholder_problem(source, text))

    def test_literal_percent_and_argument_reuse(self):
        self.assertIsNone(localize.placeholder_problem("%lld%% downloaded", "%lld%% geladen"))
        self.assertIsNone(localize.placeholder_problem("%lld%% downloaded", "%lld%% staženo"))
        self.assertIsNone(localize.placeholder_problem("%@", "%1$@ · %1$@"))
        self.assertIsNone(localize.placeholder_problem("100%", "100%"))

    def test_translations_cannot_introduce_unbounded_or_malformed_formats(self):
        for text in ["%1000000000@", "%1$1000000000@", "%l@", "%1$q"]:
            with self.subTest(text=text):
                self.assertIsNotNone(localize.placeholder_problem("%@", text))
        self.assertIsNotNone(localize.placeholder_problem("%.2lf", "%.999999999lf"))

    def test_shipped_catalogs_include_stratas_language_set_and_are_complete(self):
        expected = {"cs", "da", "de", "en", "es", "fr", "hu", "it", "ja", "ko", "nb", "nl",
                    "pl", "pt-BR", "pt-PT", "ro", "ru", "sv", "tr", "uk", "zh-Hans", "zh-Hant"}
        self.assertTrue(expected.issubset({p.stem for p in localize.FOLDER.glob("*.json")}))
        with contextlib.redirect_stdout(io.StringIO()):
            localize.check("--all", complete=True)

    def test_duplicate_keys_fail(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "en.json"
            path.write_text('{"strings":{"Save":"Save","Save":"Other"}}')
            with self.assertRaises(ValueError):
                localize.load(path)

    def test_new_language_needs_no_registry_edit(self):
        data = {"code": "cy", "language": "Cymraeg", "english": "Welsh", "plurals": ["zero", "one", "two", "few", "many", "other"]}
        self.assertEqual(localize.metadata_problems(data, "cy"), [])
        self.assertEqual(localize.plural_rules("cy", data)[0], data["plurals"])
        self.assertTrue(localize.metadata_problems(data, "../cy"))

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
