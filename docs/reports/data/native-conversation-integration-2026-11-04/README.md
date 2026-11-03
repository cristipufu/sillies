# Native conversation integration evidence

See the [report](../../native-conversation-integration-2026-11-04.md) and
[registration](../../../../Benchmarks/Chat/experiments/native-integration-2026-11-04/study.json).
All conversations, records, names and facts are synthetic. No weights or executables are included.

- `native-probes.json.gz` contains ten matched Granite follow-up pairs, nine invalidation controls,
  four installed Ministral history replays, and three deterministic fresh-session equivalence pairs.
- `granite-pairs-summary.json` reports all ten pairs, nearest-rank p95, correctness, token counts and
  process-cold opening observations. Follow-up timings include measurement and acknowledged IPC.
- `integration-scenarios.json.gz` contains the unchanged eight app scenarios for Granite and
  Ministral, including complete calls, persisted facts, raw replies and manual rubric judgments.
- Four `*-qwen.json.gz` archives contain completed frozen confirmation and reserved validation.
  Earlier partial archives in the November 3 evidence directory remain unchanged.
- `*-audit.json` reproduces the five archives' receipts, hashes and aggregates. An audit does not
  certify semantic judgments; reviews are by the implementing agent, not blinded or independent.
- `execution.json.gz` retains the bounded execution ledger, logs, driver code and Qwen resume
  provenance. The catalog mismatch was resolved using the original frozen catalog and identical
  evaluator, without changing resume validation. Native execution used 597.6 of 900 seconds.
- `integration-binaries.json` fingerprints the frozen release worker and packaged helper.
- `final-source-overlay.json.gz` captures final integration sources over the recorded base commit.
  The measured native runtime, profiles and instrumentation are unchanged. The client additionally
  gained a post-measurement idle-teardown race fix, covered by final repository regressions.
- Repository check artifacts retain the final headless completion receipt and log. The manifest
  hashes the report, registration and evidence files after validation.

Audit an archive without running a model:

```sh
python3 -B Benchmarks/Chat/benchmark.py audit \
  --archive docs/reports/data/native-conversation-integration-2026-11-04/integration-scenarios.json.gz \
  --output build/chat-benchmarks/native-integration-audit
```

These diagnostic subsets do not replace the complete leaderboard. In particular, Granite's
ambiguous quotation is retained as uncertain, Qwen's automatically passing Spanish case fails full
rubric review, and a temperature-zero replay does not rescore either production behavior.
