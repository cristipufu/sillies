# Vault qualification evidence

Read the [report](../../vault-qualification-2026-11-07.md) for conditions, conclusions and limitations.
The [procedure](../../../../Benchmarks/Vault/README.md) rebuilds the corpus and runs the real application
APIs. All records here are synthetic or refer to the public SciFact corpus; no personal Vault content
is included.

| Files | Contents |
| --- | --- |
| `corpus-manifest.json`, `expected.json` | Frozen dataset identity and independent relevance labels |
| `*-before-results.jsonl`, `*-before-scores.json` | 24-partition baseline |
| `*-64-results.jsonl`, `*-64-scores.json` | Intermediate 64-partition experiment |
| `e5-results.jsonl`, `e5-rebuilt-results.jsonl`, `apple-results.jsonl` and matching scores | Retained 96-partition policy; each result set has 335 queries |
| `*-run.json`, `e5-model-files.json` | Retrieval executable/input hashes and installed model file hashes |
| `run-summary.json`, `apple-unembedded-reasons.json` | Environment, actual embedding identities/coverage, latency summaries, validation and failed runs |
| `search.jsonl`, `concurrency.jsonl` | Million-record exact search and concurrent reader/writer/cancellation timings, in milliseconds |
| `million-vector-query.jsonl` | Separate synthetic native-index cost experiment; not an app latency benchmark |
| `million-*`, `meetings-*`, `restore-processes.jsonl`, `lifecycle-counts.json` | Complete storage operations and independent post-cleanup checks |
| `index-interruption.jsonl`, `index-recovery.jsonl` | Disposable-process interruption and derived-index recovery |
| `native-timing.json` | Native resize/scroll operations and display-link intervals, in milliseconds |

In per-query retrieval files, elapsed fields are **seconds**. Rankings contain at most five record IDs.
`fused` is a diagnostic rank merge, not the workspace's displayed list order. `exactSemantic` uses the
same persisted vectors without approximate candidates; its overlap score measures index fidelity,
not relevance. Missing embeddings and absent-information queries must be considered separately.

The scored corpus combines Wadden et al.'s *Fact or Fiction: Verifying Scientific Claims* (EMNLP 2020),
distributed through BEIR, with Sillies' authored regression cases. Claims/evidence labels are
[CC BY 4.0](https://github.com/allenai/scifact/blob/master/LICENSE.md); corpus abstracts are ODC-By 1.0
and are not included here. Recreate them from the archive/checksum in `corpus-manifest.json`.

Lifecycle source/destination paths are replaced with `<disposable-fixture>` labels. Earlier resumed
verification output used zero placeholders for preparation/activation that it did not measure; do
not treat those as restore timings. The final tool omits unmeasured fields. The million-record backup
sample explicitly predates the last query-plan fix; the fresh complete restore includes it.
