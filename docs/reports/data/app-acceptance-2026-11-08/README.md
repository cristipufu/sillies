# App acceptance evidence

See the [report](../../app-acceptance-2026-11-08.md) for conclusions and limitations.

| Files | Contents |
| --- | --- |
| `adaptive-*-results.jsonl`, `adaptive-*-scores.json` | Frozen-corpus retrieval results and existing scorer output |
| `adaptive-*-run.json` | Executable, helper, input and model identities |
| `comparison.json` | Published-baseline comparison; available-query medians and nearest-rank p95 |
| `vector-policy-million.jsonl`, `vector-policy-probe.cpp` | Alternating large-index parity/timing probe; `probes: 0` means the production C ABI, not zero searched partitions |
| `sql-*-experiments.jsonl`, `sql-experiments.jsonl` | All measured samples from rejected SQL alternatives |
| `provenance.json`, `validation.json` | Baseline/source hashes, timing definitions, startup proof and verified test receipts |
| `SHA256.json` | Evidence checksums, excluding this checksum file itself |
| `*.sql`, `sql-probe.c` | Exact query alternatives and native SQLite timing/row-score fingerprint harness |

Baseline retrieval outputs and corpus provenance remain in
[the preceding evidence bundle](../vault-search-refinement-2026-11-08). Inputs and expected judgments
are unchanged; use `Benchmarks/Vault/prepare_scifact.py`, `run_retrieval.py` and `scoring.py` as described
in `Benchmarks/Vault/README.md`. Neither model setup changes nor the live startup repair affect these
retrieval-only results. Model inference benchmarks were run without concurrent compilation.

The probe sources are retained verbatim from the experiments. The vector probe uses the earlier disposable million-vector `probe.index` fixture, links the production
`CVectorSearch` object, compares every returned candidate ID and exits nonzero on disagreement. The
four loops use the same queries and already loaded index; this is not a cold-start experiment. SQL
probes use macOS SQLite 3.51.0 and report 101 row identities/scores through a stable fingerprint. The
first query in a process may be cold and is retained rather than discarded.

Live application/window probes and local screenshots are intentionally excluded from this bundle.
