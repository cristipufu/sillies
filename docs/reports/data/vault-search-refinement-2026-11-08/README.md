# Vault search refinement evidence

See the [report](../../vault-search-refinement-2026-11-08.md) for interpretation and limits.

| Files | Meaning |
| --- | --- |
| `capacity-*-results.jsonl`, `capacity-*-scores.json` | New capacity preparation against the unchanged 335-query corpus |
| `final-*-results.jsonl`, `final-*-scores.json` | Final 433-query suite, with explicit oracle availability |
| `contended-*-results.jsonl`, `contended-*-scores.json` | Earlier verification while build/tests were active; includes Apple's transport failure and warmup misses |
| `*-run.json` | Input and executable hashes, provider/model identity |
| `coverage.json` | Prepared/searchable passage counts and actual provider identities |
| `ranking-scale-*.jsonl` | Full 15-sample release runs for the existing query and the rejected ordered prototype |
| `native-cache-probes.jsonl` | Same-system-SQLite cache-size experiment; no cache increase retained |
| `manifest.json`, `expected.json` | Expanded corpus hashes and external expectations; gold labels never enter worker inputs |
| `scorer-replay.json` | All nine prior published scores reproduced unchanged by the strengthened scorer |
| `provenance.json` | Source hashes, machine, validation receipts and timing definitions for the final runs |
| `SHA256.json` | Hashes of this evidence bundle, excluding this checksum file itself |

The baseline source is `d5a5dcf5dc0ec33f6de1ba952ea040606cc59749`. The original corpus and
baseline results remain in [the preceding qualification](../vault-qualification-2026-11-07).
The unchanged E5 files are identified by the preceding [model checksum manifest](../vault-qualification-2026-11-07/e5-model-files.json).
The expanded corpus is reconstructed using the pinned public SciFact archive and
`Benchmarks/Vault/multilingual.json`; downloaded abstracts are not committed.

Results concern disposable synthetic/public documents, not the personal Vault. First timing samples
are not controlled cold starts. The 100,000-record fixture uses random IDs; the million-record fixture
uses ordered IDs and short records. Neither fixture represents a million full recordings. The
contended measurements are retained, not silently removed from denominators. No answer-generation
or hallucination rate is inferred from retrieval-only absent-detail queries.
