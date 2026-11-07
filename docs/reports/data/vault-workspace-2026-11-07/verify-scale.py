#!/usr/bin/env python3
"""Check result completeness and arithmetic; measurements are not latency guarantees."""
import json
import math
import statistics
from pathlib import Path

DIRECTORY = Path(__file__).resolve().parent
EXPECTED_QUERIES = {
    'recent': 100,
    'broad_newest': 100,
    'recently_edited': 100,
    'broad_relevance': 100,
    'rare': 1,
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def rows(filename):
    return [json.loads(line) for line in (DIRECTORY / filename).read_text().splitlines()]


def duration(value):
    require(type(value) in (int, float) and math.isfinite(value) and value >= 0,
            'Invalid elapsed time')


def samples(values, median, p95):
    require(len(values) == 15, 'Incomplete timing samples')
    for value in values:
        duration(value)
    require(math.isclose(statistics.median(values), median, abs_tol=1e-9), 'Incorrect median')
    expected = sorted(values)[math.ceil(len(values) * 0.95) - 1]
    require(math.isclose(expected, p95, abs_tol=1e-9), 'Incorrect nearest-rank p95')


def query_results(values):
    require(len(values) == len(EXPECTED_QUERIES), 'Missing or duplicate query results')
    require({row['name'] for row in values} == set(EXPECTED_QUERIES), 'Unexpected query set')
    for row in values:
        require(row['records'] == 1_000_000, 'Wrong corpus size')
        require(row['returned'] == EXPECTED_QUERIES[row['name']], 'Wrong result count')
        require(row['loadedBodies'] == 0, 'Unexpected full-body decoding')
        samples(row['samplesMilliseconds'], row['medianMilliseconds'], row['p95Milliseconds'])


def maintenance(filename, expected_total):
    values = rows(filename)
    require(len(values) == 1, 'Incomplete maintenance run')
    row = values[0]
    require(row['visibleTotal'] == expected_total, 'Incorrect visible total')
    require(row['returned'] == min(expected_total, 100), 'Incorrect visible page')
    require(row['pending'] is True, 'Cleanup was not pending')
    require(row['loadedBodies'] == 0, 'Maintenance decoded source bodies')
    duration(row['commitMilliseconds'])
    duration(row['pageMilliseconds'])


def rejected_sample_checks(valid):
    # Completeness and percentile checks must fail on deliberately damaged results.
    invalid = [valid[:-1], valid + [valid[0]]]
    wrong_median = json.loads(json.dumps(valid))
    wrong_median[0]['medianMilliseconds'] += 1
    invalid.append(wrong_median)
    for values in invalid:
        try:
            query_results(values)
        except ValueError:
            continue
        raise ValueError('Verifier accepted damaged results')


def main():
    values = rows('scale-query-final-1m.jsonl')
    query_results(values)
    rejected_sample_checks(values)
    concurrency = rows('scale-concurrency-1m.jsonl')
    require(len(concurrency) == 1 and concurrency[0]['cancelled'] is True,
            'Missing successful cancellation')
    for name, value in concurrency[0].items():
        if name.endswith('Milliseconds') and not isinstance(value, list):
            duration(value)
    long_document = rows('scale-long-document.jsonl')
    require(len(long_document) == 1, 'Incomplete document run')
    row = long_document[0]
    require(row['sourceBytes'] == 7_200_000 and row['loadedBlocks'] == 16,
            'Unexpected document fixture')
    require(row['loadedBodies'] == 0, 'Document page decoded its full source')
    maintenance('scale-retention-1m.jsonl', 200)
    maintenance('scale-clear-1m.jsonl', 0)
    print('Scale receipts complete; counts, samples, percentiles and rejection checks pass.')


if __name__ == '__main__':
    main()
