import importlib.util
import math
import json
from pathlib import Path
import unittest

MODULE = Path(__file__).resolve().parents[1] / "Benchmarks/Vault/scoring.py"
SPEC = importlib.util.spec_from_file_location("vault_scoring", MODULE)
scoring = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(scoring)


class VaultRetrievalScoringTests(unittest.TestCase):
    def fixture(self):
        inputs = {"documents": [{"id": "a"}, {"id": "b", "tag": "other"}, {"id": "trash", "trashed": True}],
                  "queries": [{"id": "q", "text": "topic"}]}
        expected = {"q": {"group": "example", "relevant": {"a": 1}}}
        rows = [{"id": "q", "keywords": ["a"], "semantic": ["b", "a"], "fused": ["a", "b"],
                 "availability": "ready", "keywordSeconds": 0.1, "semanticSeconds": 0.2}]
        return inputs, expected, rows

    def test_hand_calculated_multiple_relevant_results(self):
        result = scoring.metrics(["wrong", "a", "b"], {"a": 1, "b": 1})
        self.assertEqual(result["hitAt5"], 1)
        self.assertEqual(result["recallAt5"], 1)
        self.assertEqual(result["precisionAt5"], 0.4)
        self.assertEqual(result["mrrAt5"], 0.5)
        self.assertAlmostEqual(result["ndcgAt5"], (1 / math.log2(3) + 0.5) / (1 + 1 / math.log2(3)))

    def test_missing_queries_duplicates_and_invalid_results_fail_closed(self):
        for change in [lambda rows: rows.clear(), lambda rows: rows.append(dict(rows[0])),
                       lambda rows: rows[0].update(semantic=["unknown"]),
                       lambda rows: rows[0].update(semantic=["a", "a"]),
                       lambda rows: rows[0].update(semantic=["trash"]),
                       lambda rows: rows[0].update(availability="unexpected"),
                       lambda rows: rows[0].update(exactSemantic=["a", "a"]),
                       lambda rows: rows[0].update(keywordSeconds=float("nan"))]:
            inputs, expected, rows = self.fixture()
            change(rows)
            with self.assertRaises(ValueError): scoring.score(inputs, expected, rows)

    def test_graded_relevance_uses_the_five_result_cutoff_and_full_positive_denominator(self):
        result = scoring.metrics(["wrong", "b", "a", "other", "another", "c"], {"a": 3, "b": 1, "c": 2})
        self.assertAlmostEqual(result["recallAt5"], 2 / 3)
        self.assertEqual(result["precisionAt5"], 0.4)
        self.assertEqual(result["mrrAt5"], 0.5)
        self.assertAlmostEqual(result["ndcgAt5"], (1 / math.log2(3) + 7 / 2) / (7 + 3 / math.log2(3) + 1 / 2))

    def test_filters_are_checked_independently_of_expected_answers(self):
        inputs, expected, rows = self.fixture()
        inputs["documents"][0]["tag"] = "wanted"
        inputs["queries"][0]["tag"] = "wanted"
        with self.assertRaises(ValueError): scoring.score(inputs, expected, rows)

    def test_absent_queries_are_not_discarded_or_counted_as_positive_hits(self):
        inputs, expected, rows = self.fixture()
        expected["q"]["relevant"] = {}
        group = scoring.score(inputs, expected, rows)["groups"]["example/semantic"]
        self.assertEqual(group["absentQueries"], 1)
        self.assertEqual(group["absentQueriesReturningSuggestions"], 1)
        self.assertNotIn("hitAt5", group)

    def test_failures_are_retained_in_the_denominator(self):
        inputs, expected, rows = self.fixture()
        rows[0].update(semantic=[], availability="timedOut")
        result = scoring.score(inputs, expected, rows)
        self.assertEqual(result["availability"], {"timedOut": 1})
        self.assertEqual(result["groups"]["example/semantic"]["hitAt5"], 0)

    def test_exact_oracle_overlap_is_independent_of_gold_relevance(self):
        inputs, expected, rows = self.fixture()
        rows[0].update(semantic=["b"], exactSemantic=["a", "b"], exactSemanticSeconds=0.3)
        result = scoring.score(inputs, expected, rows)
        self.assertEqual(result["meanExactTop5Overlap"], 0.5)
        self.assertEqual(result["exactComparisonQueries"], 1)
        self.assertEqual(result["groups"]["example/semantic"]["hitAt5"], 0)
        self.assertEqual(result["groups"]["example/exactSemantic"]["hitAt5"], 1)

    def test_incomplete_oracle_cannot_silently_reduce_the_comparison_denominator(self):
        for change in [lambda row: row.pop("exactSemantic"),
                       lambda row: row.pop("exactSemanticSeconds"),
                       lambda row: row.update(exactSemantic=None),
                       lambda row: row.update(exactSemanticSeconds=float("inf"))]:
            inputs, expected, rows = self.fixture()
            inputs["queries"].append({"id": "second", "text": "topic"})
            expected["second"] = expected["q"]
            rows[0].update(exactSemantic=["a"], exactSemanticSeconds=0.3)
            rows.append({**rows[0], "id": "second"})
            change(rows[1])
            with self.assertRaises(ValueError): scoring.score(inputs, expected, rows)

    def test_empty_exact_filter_result_is_valid_but_unsupported_scopes_are_not(self):
        inputs, expected, rows = self.fixture()
        inputs["queries"][0]["tag"] = "absent"
        expected["q"]["relevant"] = {}
        rows[0].update(keywords=[], semantic=[], fused=[], exactSemantic=[], exactSemanticSeconds=0.3)
        result = scoring.score(inputs, expected, rows)
        self.assertEqual(result["exactComparisonQueries"], 0)
        self.assertEqual(result["groups"]["example/exactSemantic"]["queries"], 1)
        inputs["queries"][0]["scope"] = "meetings"
        with self.assertRaises(ValueError): scoring.score(inputs, expected, rows)

    def test_explicitly_unavailable_oracle_counts_as_a_miss_not_a_missing_measurement(self):
        inputs, expected, rows = self.fixture()
        rows[0].update(semantic=[], availability="unavailable", exactSemantic=[],
                       exactSemanticSeconds=0.03, exactAvailability="unavailable")
        report = scoring.score(inputs, expected, rows)
        self.assertEqual(report["exactAvailability"], {"unavailable": 1})
        self.assertEqual(report["groups"]["example/exactSemantic"]["positiveQueries"], 1)
        self.assertEqual(report["groups"]["example/exactSemantic"]["hitAt5"], 0)
        self.assertEqual(report["exactComparisonQueries"], 0)
        rows[0]["exactSemantic"] = ["a"]
        with self.assertRaises(ValueError): scoring.score(inputs, expected, rows)

    def test_related_evidence_is_not_scored_as_support(self):
        inputs, expected, rows = self.fixture()
        expected["q"].update(relevant={}, relatedButInsufficient=["a"])
        report = scoring.score(inputs, expected, rows)
        self.assertEqual(report["relatedButInsufficient"]["semantic"],
                         {"queries": 1, "relatedAt1": 0, "relatedAt5": 1})
        self.assertEqual(report["groups"]["example/semantic"]["positiveQueries"], 0)
        expected["q"]["relevant"] = {"a": 1}
        with self.assertRaises(ValueError): scoring.score(inputs, expected, rows)

    def test_evidence_annotations_are_checked_against_the_source_and_filter(self):
        inputs, expected, rows = self.fixture()
        inputs["documents"][0]["text"] = "The release budget is 320 euros."
        expected["q"]["evidence"] = {"a": "320 euros"}
        scoring.validate_expectations(inputs, expected)
        expected["q"]["evidence"]["a"] = "400 euros"
        with self.assertRaises(ValueError): scoring.validate_expectations(inputs, expected)
        expected["q"]["evidence"] = {"b": "320 euros"}
        with self.assertRaises(ValueError): scoring.validate_expectations(inputs, expected)
        expected["q"].update(evidence={}, relatedButInsufficient=["trash"])
        with self.assertRaises(ValueError): scoring.validate_expectations(inputs, expected)

    def test_authored_multilingual_labels_are_complete_and_do_not_enter_worker_inputs(self):
        import sys
        from unittest.mock import patch
        with patch.dict(sys.modules, {"scoring": scoring}):
            spec = importlib.util.spec_from_file_location("prepare_vault", MODULE.with_name("prepare_scifact.py"))
            preparer = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(preparer)
        inputs, expected = {"documents": [], "queries": []}, {}
        preparer.append_cases(inputs, expected, MODULE.with_name("multilingual.json"))
        scoring.validate_expectations(inputs, expected)
        self.assertEqual(len(inputs["documents"]), 49)
        self.assertEqual(len(inputs["queries"]), 98)
        for gold in expected.values():
            self.assertEqual(set(gold.get("evidence", {})), set(gold["relevant"]))
        for query in inputs["queries"]:
            self.assertLessEqual(len(query["text"]), 200)
            self.assertTrue(set(query).isdisjoint({"relevant", "group", "language", "evidence", "relatedButInsufficient"}))
        cases = json.loads(MODULE.with_name("multilingual.json").read_text())
        languages = {query["language"] for query in cases["queries"] if query["group"] == "multilingual-native"}
        catalogs = {path.stem for path in MODULE.parents[2].joinpath("Localization").glob("*.json")}
        self.assertEqual(languages, catalogs)
        with self.assertRaises(ValueError):
            preparer.append_cases(inputs, expected, MODULE.with_name("multilingual.json"))


if __name__ == "__main__":
    unittest.main()
