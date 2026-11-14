"""Independent checks for recognition scoring and the paired publication gate."""
import importlib.util
from pathlib import Path
import sys
import unittest

PATH = Path(__file__).resolve().parents[1] / 'Benchmarks/Speech/score-quality.py'
SPEC = importlib.util.spec_from_file_location('speech_quality', PATH)
quality = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = quality
SPEC.loader.exec_module(quality)


class SpeechQualityFixtures:
    def row(self, identifier, mode, reference, hypothesis, condition='clean'):
        return {'id': identifier, 'mode': mode, 'reference': reference, 'hypothesis': hypothesis,
                'language': 'en', 'condition': condition, 'errors': [], 'processingSeconds': 1}

    def document(self, rows):
        return {'model': 'fixture', 'revision': 'fixed', 'split': 'test', 'complete': True, 'pipeline': 'meeting-disk-backed',
                'expectedResults': len(rows), 'results': rows}


class SpeechQualityTests(SpeechQualityFixtures, unittest.TestCase):
    def test_edit_counts_are_substitutions_deletions_and_insertions(self):
        result = quality.alignment('we will not ship five'.split(), 'we might ship five today'.split())
        self.assertEqual(result.total, 3)
        self.assertEqual(result.reference_words, 5)
        self.assertEqual(result.wer, 0.6)

    def test_perfect_transcript_and_silent_output_have_no_errors(self):
        self.assertEqual(quality.alignment(['yes'], ['yes']).total, 0)
        self.assertEqual(quality.alignment([], ['made', 'up']).insertions, 2)
        self.assertEqual(quality.alignment(['yes'], []).deletions, 1)

    def test_romanian_diacritics_are_not_erased_by_normalization(self):
        self.assertEqual(quality.tokens('Ștefan, nu!'), ['ștefan', 'nu'])
        self.assertNotEqual(quality.tokens('Ștefan'), quality.tokens('Stefan'))

    def test_incomplete_and_duplicate_rows_cannot_pass(self):
        rows = [self.row('one', 'baseline', 'yes', 'yes')]
        with self.assertRaises(ValueError):
            quality.score(self.document(rows))
        with self.assertRaises(ValueError):
            quality.score(self.document(rows + rows))
        document = self.document(rows)
        document['complete'] = False
        with self.assertRaises(ValueError):
            quality.score(document)

    def test_critical_word_loss_is_not_hidden_by_other_improvements(self):
        self.assertEqual(quality.critical_losses(['do', 'not', 'ship', '5'],
                                               ['do', 'not', 'ship', '5'], ['do', 'ship']), ['5', 'not'])

    def test_number_word_forms_preserve_values_without_hiding_changed_numbers(self):
        for old, new in [('10,000', 'ten,000'), ('two', '2'), ('două', 'doi')]:
            self.assertEqual(quality.critical_losses(quality.tokens(old), quality.tokens(old), quality.tokens(new)), [])
        for old, new in [('10,000', 'eleven,000'), ('two', 'to'), ('10', '')]:
            self.assertTrue(quality.critical_losses(quality.tokens(old), quality.tokens(old), quality.tokens(new)))
        self.assertEqual(quality.alignment(quality.tokens('10,000'), quality.tokens('ten,000')).total, 1)

    def test_a_subgroup_regression_blocks_an_overall_improvement(self):
        rows = [self.row('a::quiet', 'baseline', 'one two three', '', 'quiet'),
                self.row('a::quiet', 'adaptive', 'one two three', 'one two three', 'quiet'),
                self.row('b::clean', 'baseline', 'hello', 'hello'),
                self.row('b::clean', 'adaptive', 'hello', 'other')]
        report = quality.score(self.document(rows))
        self.assertFalse(report['gate_passed'])
        self.assertEqual(report['subgroup_regressions'], ['en/clean'])

    def test_identical_policies_are_not_claimed_as_an_improvement(self):
        rows = [self.row('one', mode, 'yes', 'yes') for mode in ['baseline', 'adaptive']]
        report = quality.score(self.document(rows))
        self.assertFalse(report['gate_passed'])
        self.assertTrue(report['regression_checks_passed'])

    def test_noise_only_new_words_fail_without_dividing_by_zero(self):
        rows = [self.row('noise', 'baseline', '', '', 'no-speech'),
                self.row('noise', 'adaptive', '', 'thank you', 'no-speech')]
        report = quality.score(self.document(rows))
        self.assertFalse(report['gate_passed'])
        self.assertEqual(len(report['critical_regressions']), 1)


class WindowEffectTests(SpeechQualityFixtures, unittest.TestCase):
    def traced(self, row, completion='session'):
        row.update(audioSeconds=1, inferenceRequests=1, decodedInputSamples=16000,
                   windows=[{'start': 0, 'sampleCount': 16000, 'completion': completion}],
                   inferenceWindows=[{'start': 0, 'sampleCount': 16000, 'phase': 'complete'}])
        return row

    def test_equal_input_variation_is_visible_in_raw_score_and_has_no_boundary_effect(self):
        rows = [self.traced(self.row('one', 'baseline', 'yes', 'yes')),
                self.traced(self.row('one', 'adaptive', 'yes', 'other'))]
        document = self.document(rows)
        report = quality.score_boundary_effect(document)
        self.assertFalse(report['raw']['regression_checks_passed'])
        self.assertTrue(report['boundary_effect']['regression_checks_passed'])
        self.assertEqual(report['same_input_output_variations'][0]['adaptive'], 'other')
        self.assertEqual(document['results'][1]['hypothesis'], 'other')

    def test_changed_commit_boundaries_cannot_hide_critical_losses(self):
        rows = [self.traced(self.row('one', 'baseline', 'not', 'not')),
                self.traced(self.row('one', 'adaptive', 'not', ''), completion='utterance')]
        report = quality.score_boundary_effect(self.document(rows))
        self.assertFalse(report['boundary_effect']['regression_checks_passed'])
        self.assertEqual(report['input_equivalent_pairs'], [])

    def test_missing_or_inconsistent_traces_fail_closed(self):
        rows = [self.traced(self.row('one', mode, 'yes', 'yes')) for mode in ['baseline', 'adaptive']]
        rows[0]['decodedInputSamples'] = 0
        with self.assertRaises(ValueError): quality.score_boundary_effect(self.document(rows))
        rows[0]['decodedInputSamples'] = 16000
        del rows[1]['windows']
        with self.assertRaises(ValueError): quality.score_boundary_effect(self.document(rows))


if __name__ == '__main__':
    unittest.main()
