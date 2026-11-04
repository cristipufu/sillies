# Evidence: five model opportunities

Read the [study report](../../model-opportunities-2026-11-04.md) and
[registration](../../../../Benchmarks/Chat/experiments/model-opportunities-2026-11-04/study.json)
before interpreting any numbers. All conversations and stores are synthetic.

- `contract-baseline-*`: the rebuilt starting commit, all thirteen models.
- `contract-split-wired-*`: the correctly wired six-tool experiment, three models.
- `invalid-contract-split-*`: **invalid comparisons**, because the new replacement tool was filtered
  out by the old benchmark allowlist. Preserved for diagnosis, never used to rank models.
- `contract-cache-app-*`: production conversation validation for the two enabled cache profiles.
- `*-audit.json`: checks recomputed from the frozen corpus, evidence and reviews. Reproducibility
  does not prove semantic correctness or independent validation.
- `native-probes.json.gz`: cache pairs, invalidation controls, prefix prototype measurements and
  semantic-retrieval observations. Their timing boundaries differ; do not combine their medians.
- `execution.json.gz` and `execution-ledger.json`: bounded execution, failed attempts, scripts and logs.
- `experiment-sources.json.gz` and `binary-hashes.json.gz`: experimental source and binary provenance.
  Discarded experiments are not enabled in the app; binaries and model weights are not published here.
- `final-source-overlay.json.gz`: retained implementation and regression changes against the starting commit.

Audit an app archive without running inference:

```sh
python3 -B Benchmarks/Chat/benchmark.py audit \
  --archive docs/reports/data/model-opportunities-2026-11-04/contract-baseline-apple.json.gz \
  --output /tmp/sillies-opportunities-audit
```

`SHA256SUMS` covers the published files, excluding itself. Reviews are by the implementing coding
agent and are not independent or blinded. Uncertain judgments remain outside the pass count.
