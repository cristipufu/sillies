# Vault ranking and preview evidence

See the [report](../../vault-rank-boundary-2026-11-08.md) for interpretation and limits.

| Files | Meaning |
| --- | --- |
| `combined/*-baseline.jsonl`, `combined/*-boundary.jsonl` | Final public-API release comparison; `boundary` includes both the rank boundary and indexed excerpts |
| `combined/concurrency.jsonl` | Detail reads, metadata save and cancellation during million-record search |
| `boundary-only/*.jsonl` | Earlier release comparison before indexed excerpts, including the noisy million-record runs |
| `comparison.json` | Pooled medians, nearest-rank p95, maximums and per-run medians for both stages |
| `provenance.json`, `boundary-only-source.json` | Baseline commit, release executable/source hashes, hardware and measurement policy |
| `bound-native.jsonl`, `baseline.sql`, `bound.sql`, `sql-probe.c` | Initial system-SQLite ranking experiment and exact query shapes |
| `excerpt-native.jsonl`, `excerpt-*.sql`, `excerpt-probe.c` | System-SQLite excerpt comparison; setup time is included for the indexed selection |
| `public-corpus-query-parity.json`, `check-query-parity.py` | Exact ID/score/block parity on 24 public-corpus queries; not a relevance or answer-quality score |
| `validation.json` | Checked-test completion receipts |
| `SHA256.json` | Evidence checksums, excluding the checksum file itself |

Retain release `VaultScaleBenchmark` binaries for baseline `926b026` and the changed sources, then use
the same synthetic fixtures for both. The retained earlier reference binary has identical keyword
ranking and text-search plan sources to `926b026`; the benchmark's intervening change adds random-ID
seeding, without changing its query workload. Exact executable hashes are in `provenance.json`.

The fixture generator and public commands are documented in the [Vault guide](../../../contributing/vault.md).
Use `seed-random` for the 100,000-record fixture and `seed` for the million-record fixture. Random UUIDs
vary between freshly generated fixtures. Never point these tools at the personal Vault. The retained
`compare-release.py` scripts show run order, per-process deadlines and receipt checks. They reference
the original local build paths; supply equivalent retained binaries and fixture directories when
reproducing elsewhere. The probe sources are retained as used for the experiments.

Every final condition has two runs of 15 samples for each of five operations. Both release stages
retain every sample, including initialization and slow observations. The files label a run's selected
15-sample middle value as its median; `comparison.json` pools 30 values and uses the arithmetic mean
of the two middle values. `loadedBodies` is the writer-owned counter returned by `VaultLibrary.metrics()`;
it does not aggregate the separate search reader. Direct read-only persistence tests cover that reader's
body-loading invariant. Native SQLite probes use macOS SQLite 3.51.0. The public-corpus parity check records its Python SQLite version and
serves only as a correctness cross-check, not as app performance evidence.

These disposable short-record fixtures and public corpus contain no personal Vault content. The
isolated excerpt test intentionally spreads its 100 selected IDs throughout the fixture; its timing
must not be reported as a complete Vault search.
