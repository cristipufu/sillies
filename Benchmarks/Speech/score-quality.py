#!/usr/bin/env python3
"""Score complete paired native-recognition results; refuse subgroup and critical-word regressions."""
import argparse
from collections import Counter, defaultdict
from dataclasses import asdict, dataclass
import json
from pathlib import Path
import random
import unicodedata


BOOTSTRAP_REPETITIONS = 2000
BOOTSTRAP_SEED = 473
CONFIDENCE_TAIL = 0.025


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
# Deliberately do not equate homophones ("to", "for") or infer missing number multipliers.
CARDINAL_FORMS = {
    **{word: str(value) for value, word in enumerate(
        'zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen'.split())},
    **dict(zip('twenty thirty forty fifty sixty seventy eighty ninety'.split(), map(str, range(20, 100, 10)))),
    **{word: str(value) for value, word in enumerate('zero unu doi trei patru cinci șase șapte opt nouă zece'.split())},
    'una': '1', 'două': '2',
}


def critical_losses(reference, baseline, adaptive):
    def canonical(words):
        return [CARDINAL_FORMS.get(word, word) for word in words]
    truth_words, old_words, new_words = map(canonical, [reference, baseline, adaptive])
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
        if lost or lost_utterance or new_noise_words:
            regressions.append({'id': identifier, 'critical_losses': lost, 'hypothesis': new['hypothesis']})
        cases.append({'id': identifier, 'baseline': asdict(before), 'adaptive': asdict(after),
                      'baseline_wer': before.wer, 'adaptive_wer': after.wer,
                      'baseline_seconds': old['processingSeconds'], 'adaptive_seconds': new['processingSeconds']})
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
            'regression_checks_passed': not critical_regressions and not subgroup_regressions,
            'gate_passed': passed, 'cases': cases}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('results', type=Path)
    parser.add_argument('output', type=Path)
    arguments = parser.parse_args()
    result = score(json.loads(arguments.results.read_text()))
    arguments.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({key: value for key,value in result.items() if key not in {'groups','cases','critical_regressions'}}, indent=2))

    raise SystemExit(0 if result['gate_passed'] else 1)
