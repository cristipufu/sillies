"""Review reuse must not turn changed answers, provenance or tools into unexamined passes."""
import copy
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

path = Path(__file__).resolve().parents[1] / "scripts/recheck-chat-reviews.py"
spec = importlib.util.spec_from_file_location("chat_review_equivalence", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

from test_chat_benchmark_audit import prepare_run, receipt_for, rubric_review, sample_case


class ReviewEquivalenceTests(unittest.TestCase):
    def setUp(self):
        self.turn = {"input": "What did we discuss?", "reply": "A garden.", "rubric": "Recall the garden.",
                     "checks": [{"passed": True}], "memories": [{"value": "garden", "source": "My garden"}],
                     "calls": [{"name": "search_conversation", "arguments": '{"query":"garden"}',
                                "result": '[{"messageID":"random-a","speaker":"user","excerpt":"A garden"}]'}]}

    def test_only_incidental_timing_and_generated_history_ids_can_change(self):
        changed = copy.deepcopy(self.turn)
        changed["seconds"] = 999
        changed["calls"][0]["result"] = '[{"excerpt":"A garden","speaker":"user","messageID":"random-b"}]'
        self.assertEqual(module.task_evidence(self.turn), module.task_evidence(changed))

    def test_changed_task_output_state_and_evidence_require_fresh_review(self):
        mutations = [
            lambda t: t.update(reply="A forest."),
            lambda t: t.update(rubric="A different task"),
            lambda t: t["memories"][0].update(source="A question, not an assertion"),
            lambda t: t["calls"][0].update(arguments='{"query":"forest"}'),
            lambda t: t["calls"][0].update(result='[{"speaker":"companion","excerpt":"A garden"}]'),
            lambda t: t["calls"][0].update(result='[{"speaker":"user","excerpt":"A forest"}]'),
            lambda t: t.update(compactionCalls=8),
        ]
        for mutate in mutations:
            changed = copy.deepcopy(self.turn)
            mutate(changed)
            self.assertNotEqual(module.task_evidence(self.turn), module.task_evidence(changed))

    def test_vault_record_ids_are_evidence_not_discarded_metadata(self):
        first = {"calls": [{"name": "read_vault_record", "arguments": '{"recordID":"a"}', "result": "Body"}]}
        changed = copy.deepcopy(first)
        changed["calls"][0]["arguments"] = '{"recordID":"b"}'
        self.assertNotEqual(module.task_evidence(first), module.task_evidence(changed))

    def test_recheck_rejects_tampered_receipt_even_if_stored_hashes_still_match(self):
        with tempfile.TemporaryDirectory() as directory:
            source, destination = Path(directory) / "old", Path(directory) / "new"
            case = sample_case()
            _, receipt = receipt_for(case)
            for run in (source, destination):
                prepare_run(run, [case])
                folder = run / "apple/cases"
                folder.mkdir(parents=True)
                (folder / f"{receipt['job']}.json").write_text(json.dumps(receipt))
            (source / "reviews.json").write_text(json.dumps([rubric_review(receipt)]))
            receipt["turns"][0]["memories"] = [{"key": "name", "value": "Fabricated"}]
            (source / "apple/cases" / f"{receipt['job']}.json").write_text(json.dumps(receipt))
            with self.assertRaisesRegex(ValueError, "Evidence hash mismatch"):
                module.recheck(source, destination, "apple")
            self.assertFalse((destination / "reviews.json").exists())
