"""Offline checks for reviewed download metadata; inference never consults this generator."""
import dataclasses
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("text_catalog", ROOT / "scripts/update-text-catalog.py")
catalog = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = catalog
SPEC.loader.exec_module(catalog)


class TextCatalogTests(unittest.TestCase):
    def test_bundled_descriptors_match_reviewed_metadata(self):
        bundled = json.loads((ROOT / "Sources/SilliesModelStore/Resources/text-models.json").read_text())
        expected = [catalog.descriptor(model) for model in catalog.MODELS]
        self.assertEqual([item["model"] for item in bundled["manifests"]], expected)
        self.assertEqual(len({item["id"] for item in expected}), len(expected))

    def test_license_and_original_release_survive_generation(self):
        model = dataclasses.replace(catalog.MODELS[0], license="Custom license",
                                    release_date="2026-08-04", reasoning="alwaysOnThinkTags")
        result = catalog.descriptor(model)
        self.assertEqual(result["license"], "Custom license")
        self.assertEqual(result["release"]["date"], "2026-08-04")
        self.assertEqual(result["release"]["sourceURL"], model.release_source)
        self.assertEqual(result["reasoning"], "alwaysOnThinkTags")
        with self.assertRaises(ValueError):
            catalog.descriptor(dataclasses.replace(model, release_date="2026-02-30"))

    def test_each_model_owns_a_profile_and_checkpoint_changes_require_review(self):
        profiles = {path.stem for path in (ROOT / "ModelProfiles/Text").glob("*.json")}
        self.assertEqual(profiles, {model.identifier for model in catalog.MODELS})
        for model in catalog.MODELS:
            with self.subTest(model=model.identifier):
                with self.assertRaisesRegex(ValueError, "exact checkpoint"):
                    catalog.profile(dataclasses.replace(model, revision="0" * 40))

    def test_profile_refresh_is_offline_and_preserves_downloads(self):
        path = ROOT / "Sources/SilliesModelStore/Resources/text-models.json"
        original = json.loads(path.read_text())
        with patch.object(catalog, "read", side_effect=AssertionError("Must stay offline")):
            refreshed = catalog.refresh_descriptors(path)
        self.assertEqual(refreshed, original)

    def test_large_tokenizer_without_lfs_is_bounded_and_hashed(self):
        data = b"x" * (2 * 1024 * 1024)
        entry = {"rfilename": "tokenizer.json", "size": len(data)}
        with patch.object(catalog, "read", return_value=data) as read:
            result = catalog.artifact(catalog.MODELS[0], entry)
        self.assertEqual(result["sha256"], hashlib.sha256(data).hexdigest())
        self.assertEqual(read.call_args.kwargs["maximum_bytes"], catalog.MAXIMUM_SUPPORT_BYTES)

    def test_weights_without_remote_hash_and_oversized_support_are_rejected(self):
        entries = [{"rfilename": "model.safetensors", "size": 1},
                   {"rfilename": "tokenizer.json", "size": catalog.MAXIMUM_SUPPORT_BYTES + 1}]
        with patch.object(catalog, "read") as read:
            for entry in entries:
                with self.assertRaises(ValueError):
                    catalog.artifact(catalog.MODELS[0], entry)
            read.assert_not_called()

    def test_small_file_length_mismatch_is_not_published(self):
        with patch.object(catalog, "read", return_value=b"short"):
            with self.assertRaisesRegex(ValueError, "length mismatch"):
                catalog.artifact(catalog.MODELS[0], {"rfilename": "config.json", "size": 9})


if __name__ == "__main__":
    unittest.main()
