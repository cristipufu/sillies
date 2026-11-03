# Frozen application-strategy evidence

See the [report](../../app-strategies-2026-11-03.md) and
[registered plan](../../app-strategies-plan-2026-11-03.md) for decisions and limitations.
The control is `c49e499ff46f7789348b7b7cfad97b811682ddbd`, with the existing benchmark's
memory-commit timing instrumentation. All conversation content is synthetic.

- `*-development.json.gz`: the original eight-scenario screen across thirteen models.
- `*-context-probe.json.gz`: older-history controls; coverage includes explicit non-admission.
- `*-confirmation*.json.gz` and `*-validation*.json.gz`: additional matched repetitions and reserved tasks.
- `*-sources.json.gz`: exact source overlays used to build the frozen workers/helper.
- `split-writes.patch`, `memory-context.patch`, `cache.patch`: readable prototype changes against the control.
- `native-probes.json.gz`: cache plans, every matched native observation, template comparisons, and the Ministral tokenizer-only controls.
- `execution.json.gz`: the bounded supervisor ledger, logs, admission decisions and experiment-driver sources.
- `summary.json`: reviewed task counts and coverage, separately from the published model leaderboard.
- `repository-check.json` and `repository-check.log.gz`: the completed `make check` receipt and full log after restoring production behavior.
- `manifest.json`: SHA-256 hashes for the retained files.

Each benchmark archive embeds its corpus, model/runtime metadata, calls, persisted facts and
hash-bound manual reviews. Audit checks recorded evidence and aggregates; it does not certify
semantic judgments. Reviews were performed by the same agent conducting the study, not an
independent or blinded human reviewer.

```sh
python3 -B Benchmarks/Chat/benchmark.py audit \
  --archive docs/reports/data/app-strategies-2026-11-03/baseline-development.json.gz \
  --output build/chat-benchmarks/app-strategies-audit
```

The standard `app` profile normally has five tools. The split-write prototype has **six**, as
shown by its captured native requests; older generated profile labels still describe the standard
five-tool profile. Use the study report and actual requests when comparing this variant.

The source overlays preserve experiments for inspection and reproduction. Production inference
behavior was restored after the study. No experimental model policy, native cache implementation,
new dependency, model download, app restart or leaderboard replacement was included.
