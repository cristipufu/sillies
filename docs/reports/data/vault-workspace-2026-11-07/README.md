# Vault workspace qualification data

See the [report](../../vault-workspace-2026-11-07.md) for interpretation and limitations.
The data contains only synthetic fixtures, not a personal Vault.

| Files | What they measure |
| --- | --- |
| `scale-fixture.json` | Final schema-3 corpus: one million short synthetic captures, five million content blocks, no pending backfill |
| `scale-query-final-1m.jsonl` | Release-build query samples in execution order; 15 per query; native block/header read path |
| `scale-concurrency-1m.jsonl` | Independent detail/save work during a broad search, then cancellation and reader reuse |
| `scale-long-document.jsonl` | Create a 7.2 MB note, read/edit a middle block page |
| `scale-retention-1m.jsonl`, `scale-clear-1m.jsonl` | Persist a deletion request and return its snapshot/page; physical cleanup remains pending |
| `scale-clear-before-empty-page-fix.jsonl` | Earlier clear request that still scanned for headers after obtaining an empty count |
| `scale-clear-before-visibility-gate.jsonl` | Intermediate clear with a fast acknowledgement but a slow first empty workspace page |
| `semantic-native-*.jsonl` | Frozen 76-query text fixture through the real local E5 helper and Vault pipeline |
| `semantic-positive-retrieval.json` | Positive hit-at-five comparison only; not a precision or privacy score |
| `faiss-*.json`, `faiss-probe.cpp` | Synthetic clustered-vector ANN prototype and exact-reference comparison |

Run `python3 verify-scale.py` and `python3 score-retrieval.py` from this folder (or use their
repository-relative paths). The scale verifier checks complete query receipts, returned counts,
finite timings, sample counts, median/nearest-rank p95 arithmetic, cancellation and deliberate
malformed-result rejection. It does not claim timing stability or judge whether returned prose is useful.

The OS file cache was not controlled. Fifteen samples produce a nearest-rank p95 equal to the maximum;
this is too small a sample to establish a stable tail. The first broad relevance read was substantially
slower than subsequent reads. The separate maintenance runs use disposable APFS clones of the same
fixture. The visibility covering index was added to that owned fixture using the exact production DDL
before the final measurements; it changes no logical records.

Reproduction commands are in [the contribution guide](../../../contributing/vault.md#verification).
Use a disposable directory. Seeding is resumable in 20-second slices; query and maintenance commands
need an external deadline (180 seconds used here). No multi-hour blocking run was used.
