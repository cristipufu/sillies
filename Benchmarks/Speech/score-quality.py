#!/usr/bin/env python3
"""Score complete paired native-recognition results; refuse subgroup and critical-word regressions."""
import argparse
from collections import Counter, defaultdict
from dataclasses import asdict, dataclass
import copy
import hashlib
import math
import json
from pathlib import Path
import random
import unicodedata


BOOTSTRAP_REPETITIONS = 2000
BOOTSTRAP_SEED = 473
CONFIDENCE_TAIL = 0.025
MAX_WINDOW_MEASUREMENTS = 1024
MAX_DRAFT_BYTES = 64 * 1024
WINDOW_SAMPLE_RATE = 16000
MAX_WINDOW_SECONDS = 12
MAX_FIXTURE_SECONDS = 90
AUDIO_TIME_TOLERANCE = 1e-6


def tokens(text):
    normalized = unicodedata.normalize('NFKC', text).casefold().replace('’', "'")
    return ''.join(char if char.isalnum() or char == "'" else ' ' for char in normalized).split()


@dataclass
class Errors:
    substitutions: int = 0
    deletions: int = 0
    insertions: int = 0
    reference_words: int = 0

    @property
    def total(self):
        return self.substitutions + self.deletions + self.insertions

    @property
    def wer(self):
        return self.total / self.reference_words if self.reference_words else 0.0

    def add(self, other):
        self.substitutions += other.substitutions
        self.deletions += other.deletions
        self.insertions += other.insertions
        self.reference_words += other.reference_words


def alignment(reference, hypothesis):
    rows = [[(i + j, 0, i, j) for j in range(len(hypothesis) + 1)] for i in range(len(reference) + 1)]
    for i, left in enumerate(reference, 1):
        for j, right in enumerate(hypothesis, 1):
            diagonal = rows[i-1][j-1]
            deletion = rows[i-1][j]
            insertion = rows[i][j-1]
            choices = [
                (diagonal[0] + (left != right), diagonal[1] + (left != right), diagonal[2], diagonal[3]),
                (deletion[0] + 1, deletion[1], deletion[2] + 1, deletion[3]),
                (insertion[0] + 1, insertion[1], insertion[2], insertion[3] + 1),
            ]
            rows[i][j] = min(choices, key=lambda value: value[0])
    _, substitutions, deletions, insertions = rows[-1][-1]
    return Errors(substitutions, deletions, insertions, len(reference))


# Numeric word forms are equivalent for value retention; WER still scores the original tokens.
# Explicit multipliers are parsed; missing multipliers and homophones are never inferred.
ENGLISH_CARDINAL_FORMS = {
    **{word: str(value) for value, word in enumerate(
        'zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen'.split())},
    **dict(zip('twenty thirty forty fifty sixty seventy eighty ninety'.split(), map(str, range(20, 100, 10)))),
}
CARDINAL_FORMS = {
    **ENGLISH_CARDINAL_FORMS,
    **{word: str(value) for value, word in enumerate('zero unu doi trei patru cinci șase șapte opt nouă zece'.split())},
    'una': '1', 'două': '2',
}
NUMBER_SCALES = [('trillion', 10**12), ('billion', 10**9), ('million', 10**6), ('thousand', 1000)]
NUMBER_WORDS = set(ENGLISH_CARDINAL_FORMS) | {name for name, _ in NUMBER_SCALES} | {'hundred', 'and'}
MAX_NUMERAL_WORDS = 32


def number_below_hundred(words):
    if not words or any(word not in ENGLISH_CARDINAL_FORMS for word in words):
        return None
    values = [int(ENGLISH_CARDINAL_FORMS[word]) for word in words]
    if len(values) == 1:
        return values[0]
    if len(values) == 2 and values[0] >= 20 and values[0] % 10 == 0 and 1 <= values[1] <= 9:
        return sum(values)
    return None


def number_below_thousand(words):
    if len(words) >= 2 and words[1] == 'hundred':
        first = number_below_hundred(words[:1])
        remainder = words[2:]
        if remainder[:1] == ['and']:
            remainder = remainder[1:]
            if not remainder:
                return None
        last = number_below_hundred(remainder) if remainder else 0
        if first is not None and 1 <= first <= 9 and last is not None:
            return first * 100 + last
        return None
    return number_below_hundred(words)


def number_expression(words):
    for name, scale in NUMBER_SCALES:
        if name not in words:
            continue
        if words.count(name) != 1:
            return None
        split = words.index(name)
        first = number_below_thousand(words[:split])
        remainder = words[split + 1:]
        if remainder[:1] == ['and']:
            remainder = remainder[1:]
            if not remainder:
                return None
        last = number_expression(remainder) if remainder else 0
        if first is not None and first > 0 and last is not None and last < scale:
            return first * scale + last
        return None
    return number_below_thousand(words)


def canonical_values(words):
    result, index = [], 0
    while index < len(words):
        end = index
        if words[index] in ENGLISH_CARDINAL_FORMS:
            while end < len(words) and end - index < MAX_NUMERAL_WORDS and words[end] in NUMBER_WORDS:
                end += 1
        while end > index:
            value = number_expression(words[index:end])
            if value is not None:
                result.append(str(value))
                break
            end -= 1
        if end == index:
            result.append(CARDINAL_FORMS.get(words[index], words[index]))
            end += 1
        index = end
    return result


def critical_losses(reference, baseline, adaptive):
    truth_words, old_words, new_words = map(canonical_values, [reference, baseline, adaptive])
    watched = {word for word in truth_words if word in {'no', 'not', 'never', 'nu', 'niciodată'} or any(c.isdigit() for c in word)}
    old, new, truth = Counter(old_words), Counter(new_words), Counter(truth_words)
    return sorted(word for word in watched if min(new[word], truth[word]) < min(old[word], truth[word]))


def validated_pairs(document):
    if document.get('pipeline') != 'meeting-disk-backed':
        raise ValueError('Quality results must exercise the production meeting backing-store path')
    if not document['complete'] or len(document['results']) != document['expectedResults']:
        raise ValueError('Missing native completion receipt or result rows')
    pairs = defaultdict(dict)
    for result in document['results']:
        if result['mode'] in pairs[result['id']] or result['errors']:
            raise ValueError('Duplicate policy row or native recognition failure')
        if 'draftHypotheses' in result:
            drafts = result['draftHypotheses']
            if (not isinstance(drafts, list) or len(drafts) > MAX_WINDOW_MEASUREMENTS
                    or not all(isinstance(text, str) for text in drafts)
                    or sum(len(text.encode('utf-8')) for text in drafts) > MAX_DRAFT_BYTES):
                raise ValueError('Draft trace exceeds its content bound')
        pairs[result['id']][result['mode']] = result
    for pair in pairs.values():
        if set(pair) != {'baseline', 'adaptive'}:
            raise ValueError('Unpaired recognition fixture')
        old, new = pair['baseline'], pair['adaptive']
        if any(old[key] != new[key] for key in ['reference', 'language', 'condition']):
            raise ValueError('Paired inputs differ')
    return pairs


def compare_pairs(pairs):
    groups = defaultdict(lambda: {'baseline': Errors(), 'adaptive': Errors()})
    regressions, cases = [], []
    for identifier, pair in pairs.items():
        old, new = pair['baseline'], pair['adaptive']
        reference = tokens(old['reference'])
        old_words, new_words = tokens(old['hypothesis']), tokens(new['hypothesis'])
        before, after = alignment(reference, old_words), alignment(reference, new_words)
        group = old['language'] + '/' + old['condition']
        groups[group]['baseline'].add(before)
        groups[group]['adaptive'].add(after)
        lost = critical_losses(reference, old_words, new_words)
        lost_utterance = reference and old_words and not new_words
        new_noise_words = not reference and len(new_words) > len(old_words)
        draft_words = {mode: max((len(tokens(text)) for text in row['draftHypotheses']), default=0)
                       if 'draftHypotheses' in row else None for mode, row in pair.items()}
        new_noise_draft = (not reference and None not in draft_words.values()
                           and draft_words['adaptive'] > draft_words['baseline'])
        if lost or lost_utterance or new_noise_words or new_noise_draft:
            regressions.append({'id': identifier, 'critical_losses': lost, 'hypothesis': new['hypothesis'],
                                'draft_noise_increase': bool(new_noise_draft)})
        cases.append({'id': identifier, 'baseline': asdict(before), 'adaptive': asdict(after),
                      'baseline_wer': before.wer, 'adaptive_wer': after.wer,
                      'baseline_seconds': old['processingSeconds'], 'adaptive_seconds': new['processingSeconds'],
                      'maximum_draft_words': draft_words})
    return groups, regressions, cases


def summarize_groups(groups):
    totals = {'baseline': Errors(), 'adaptive': Errors()}
    regressions, summary = [], {}
    for name, values in groups.items():
        for mode in totals:
            totals[mode].add(values[mode])
        if values['adaptive'].total > values['baseline'].total:
            regressions.append(name)
        summary[name] = {mode: {**asdict(value), 'wer': value.wer} for mode, value in values.items()}
    return totals, regressions, summary


def bootstrap_delta(cases):
    # Variants of one recording form a cluster; generated conditions are not independent evidence.
    clusters = defaultdict(list)
    for case in cases:
        if case['baseline']['reference_words']:
            clusters[case['id'].split('::')[0]].append(case)
    if not clusters:
        return [0, 0]
    rng, differences, keys = random.Random(BOOTSTRAP_SEED), [], sorted(clusters)
    for _ in range(BOOTSTRAP_REPETITIONS):
        sampled = [case for _ in keys for case in clusters[rng.choice(keys)]]
        words = sum(case['baseline']['reference_words'] for case in sampled)
        errors = {mode: sum(sum(case[mode][key] for key in ['substitutions', 'deletions', 'insertions'])
                            for case in sampled) for mode in ['baseline', 'adaptive']}
        differences.append((errors['adaptive'] - errors['baseline']) / words)
    differences.sort()
    return [differences[int(BOOTSTRAP_REPETITIONS * CONFIDENCE_TAIL) - 1],
            differences[int(BOOTSTRAP_REPETITIONS * (1 - CONFIDENCE_TAIL)) - 1]]


def score(document):
    pairs = validated_pairs(document)
    groups, critical_regressions, cases = compare_pairs(pairs)
    totals, subgroup_regressions, summary = summarize_groups(groups)
    interval = bootstrap_delta(cases)
    passed = (not critical_regressions and not subgroup_regressions
              and totals['adaptive'].total < totals['baseline'].total and interval[1] < 0)
    return {'model': document['model'], 'revision': document['revision'], 'split': document['split'],
            'paired_fixtures': len(pairs), 'totals': {m: {**asdict(v), 'wer': v.wer} for m, v in totals.items()},
            'groups': summary, 'paired_wer_delta_95ci': interval, 'critical_regressions': critical_regressions,
            'subgroup_regressions': subgroup_regressions,
            'draft_noise_pairs_checked': sum(not pair['baseline']['reference'].strip()
                and all('draftHypotheses' in row for row in pair.values()) for pair in pairs.values()),
            'regression_checks_passed': not critical_regressions and not subgroup_regressions,
            'gate_passed': passed, 'cases': cases}


def validate_window_trace(row):
    windows, inferences = row.get('windows'), row.get('inferenceWindows')
    if windows is None or inferences is None or max(len(windows), len(inferences)) > MAX_WINDOW_MEASUREMENTS:
        raise ValueError('Boundary attribution requires bounded native window traces')
    if not math.isfinite(row['audioSeconds']) or not 0 < row['audioSeconds'] <= MAX_FIXTURE_SECONDS:
        raise ValueError('Audio duration exceeds its trace bound')
    if not windows and row['hypothesis'].strip():
        raise ValueError('Transcript has no processing window')
    if len(inferences) != row['inferenceRequests'] or sum(w['sampleCount'] for w in inferences) != row['decodedInputSamples']:
        raise ValueError('Inference trace does not match work accounting')
    for window in windows + inferences:
        if (not math.isfinite(window['start']) or window['start'] < 0
                or not 0 < window['sampleCount'] <= MAX_WINDOW_SECONDS * WINDOW_SAMPLE_RATE
                or window['start'] + window['sampleCount'] / WINDOW_SAMPLE_RATE > row['audioSeconds'] + AUDIO_TIME_TOLERANCE):
            raise ValueError('Window trace exceeds its audio bounds')
    phases = {'draft': {'partial'}, 'boundary': {'boundary', 'complete'}, 'utterance': {'complete'}, 'session': {'complete'}}
    if any(w['completion'] not in phases for w in windows):
        raise ValueError('Unknown window completion')
    for inference in inferences:
        if not any(w['start'] == inference['start'] and w['sampleCount'] == inference['sampleCount']
                   and inference['phase'] in phases[w['completion']] for w in windows):
            raise ValueError('Inference has no matching window decision')


def score_boundary_effect(document):
    if document.get('comparison', {}).get('kind') == 'end-to-end':
        raise ValueError('End-to-end comparisons must retain actual outcomes; equal window traces do not establish equal decoding policy or preprocessing')
    pairs = validated_pairs(document)
    controlled = copy.deepcopy(document)
    equivalent, variations = [], []
    for identifier, pair in pairs.items():
        old, new = pair['baseline'], pair['adaptive']
        for row in pair.values():
            validate_window_trace(row)
        if old['audioSeconds'] != new['audioSeconds']:
            raise ValueError('Paired audio durations differ')
        if old['windows'] == new['windows'] and old['inferenceWindows'] == new['inferenceWindows']:
            equivalent.append(identifier)
            if old['hypothesis'] != new['hypothesis']:
                variations.append({'id': identifier, 'baseline': old['hypothesis'], 'adaptive': new['hypothesis']})
    # Equal audio windows and decode calls cannot attribute decoder randomness to the boundary policy.
    # Keep every raw outcome separately; use one shared output only for this controlled effect estimate.
    for row in controlled['results']:
        if row['mode'] == 'adaptive' and row['id'] in equivalent:
            row['hypothesis'] = pairs[row['id']]['baseline']['hypothesis']
    return {'raw': score(document), 'boundary_effect': score(controlled),
            'input_equivalent_pairs': equivalent, 'same_input_output_variations': variations}


def compare_versions(baseline, candidate, baseline_mode='baseline', candidate_mode='adaptive'):
    """Compare shipped and candidate behavior while preserving their complete source reports."""
    before, after = validated_pairs(baseline), validated_pairs(candidate)
    if baseline_mode not in {'baseline', 'adaptive'} or candidate_mode not in {'baseline', 'adaptive'}:
        raise ValueError('Unknown comparison policy')
    for key in ['model', 'revision', 'manifestSHA256', 'split', 'feed']:
        if key not in baseline or baseline[key] != candidate.get(key):
            raise ValueError('Cross-version models, inputs or delivery differ: ' + key)
    if before.keys() != after.keys():
        raise ValueError('Cross-version fixture sets differ')
    rows = []
    for identifier, pair in before.items():
        old, new = pair[baseline_mode], after[identifier][candidate_mode]
        if any(old[key] != new[key] for key in ['reference', 'language', 'condition', 'audioSeconds']):
            raise ValueError('Cross-version paired fixture differs: ' + identifier)
        rows += [{**old, 'mode': 'baseline'}, {**new, 'mode': 'adaptive'}]
    return {**baseline, 'results': rows, 'expectedResults': len(rows),
            'comparison': {'kind': 'end-to-end', 'baselineMode': baseline_mode, 'candidateMode': candidate_mode}}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('results', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--comparison', choices=['raw', 'boundary-effect'], default='raw')
    parser.add_argument('--baseline', type=Path, help='Complete native report from the shipped executable')
    parser.add_argument('--baseline-mode', choices=['baseline', 'adaptive'], default='baseline')
    parser.add_argument('--candidate-mode', choices=['baseline', 'adaptive'], default='adaptive')
    arguments = parser.parse_args()
    candidate_bytes = arguments.results.read_bytes()
    document = json.loads(candidate_bytes)
    if arguments.baseline:
        baseline_bytes = arguments.baseline.read_bytes()
        document = compare_versions(json.loads(baseline_bytes), document, arguments.baseline_mode, arguments.candidate_mode)
        document['comparison'].update(baselineReportSHA256=hashlib.sha256(baseline_bytes).hexdigest(),
                                      candidateReportSHA256=hashlib.sha256(candidate_bytes).hexdigest())
    result = score(document) if arguments.comparison == 'raw' else score_boundary_effect(document)
    if arguments.baseline:
        result['comparison'] = document['comparison']
    arguments.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    decision = result if arguments.comparison == 'raw' else result['boundary_effect']
    print(json.dumps({key: value for key,value in decision.items() if key not in {'groups','cases','critical_regressions'}}, indent=2))

    raise SystemExit(0 if decision['gate_passed'] else 1)
