# Cache and memory follow-up evidence

The [report](../../cache-memory-2026-11-04.md) explains the promoted changes and unresolved model
behavior. The [registration](../../../../Benchmarks/Chat/experiments/cache-memory-2026-11-04/study.json)
and [frozen tasks](../../../../Benchmarks/Chat/experiments/cache-memory-2026-11-04/corpus/cases.json)
record budgets, controls and rubrics.

- `native-probes.json.gz`: 20 matched follow-up pairs, 18 invalidation controls, 6 process-cold
  preparation traces and 10 fresh raw/native equivalence pairs, with synthetic requests.
- `app-*.json.gz`: four complete app-task runs with replies, requests, tools, persisted fact snapshots,
  profiles, timings and hash-bound manual judgments. Each contains 10 tasks and 11 turns.
- `app-*-audit.json`: recomputed evidence/scoring integrity, not a quality certification.
- `execution.json.gz`: the cumulative 692.6/1,200-second native ledger, complete logs, stderr and
  standard-library process drivers. Drivers supervise native Swift; no Python model runtime is used.
- `binaries.json`: executed artifacts and the unused first candidate-worker build.
- `source-overlay.json.gz`: changed source/tests/profiles over commit `8716a94`, including the
  presentation-only additions after native inference.
- `targeted-check.log.gz`, `repository-check.log.gz`, `repository-check.json`: targeted scale/mutation
  regressions and the successful final headless `make check`, including discovered-test receipts.

The earlier comparison worker is the preceding study's frozen release, not a fresh build of the
base commit; the report discloses its idle-cleanup difference. Raw/native cache controls use the same
binary and identical requests apart from session identity. Do not reinterpret the diagnostic task
scores as a revised leaderboard, and do not count the deterministic replays as repairs of failed
stochastic tasks. Manual reviews are by the implementing agent, not independent or blinded.

To audit any app archive without inference:

```sh
python3 -B Benchmarks/Chat/benchmark.py audit \
  --archive docs/reports/data/cache-memory-2026-11-04/app-candidate-granite-4.2-3b.json.gz \
  --output build/cache-memory-audit
```

`manifest.json` hashes the report, registration, corpus and every evidence file except itself.
