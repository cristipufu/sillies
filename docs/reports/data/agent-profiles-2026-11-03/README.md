# Agent profile experiment evidence

See the [engineering report](../../agent-profiles-2026-11-03.md) for interpretation and limitations.

- `baseline.json.gz`: fresh committed-code comparison, 192 cases / 288 reviewed turns.
- `candidate-final.json.gz`: the frozen main comparison, 192 cases / 288 reviewed turns. The name
  refers to the main experiment stage; it predates the later protocol and combined-budget fixes.
- `apple-measured-control.json.gz`: the rejected intermediate Apple tool-result-tokenization
  control. Only Apple ran (24 cases / 36 reviewed turns); its wider scheduled coverage is explicitly
  incomplete and it is excluded from main comparative analysis.
- `measurements-main.json`: measurements reproduced from the two complete, reviewed main archives.
- `capacity-4k.json.gz`, `capacity-8k.json.gz`: the later checked binary at two context sizes;
  each archive contains 18 cases / 30 reviewed turns across three models.
- `boundary-8k.json.gz`, `boundary-gemma12-8k.json.gz`: one forced-compaction case per model.
  Both first turns timed out. Unexecuted follow-ups remain failed, with three reviewed turns each.
- `measurements.json`: main and capacity measurements plus the boundary failures, kept separate.
- `plan.json`, `schedule-final.json`, `capacity-plan.json`, `boundary*-plan.json`: declared
  scenarios, ordering and limits. Capacity and boundary corpus copies are embedded in the archives.
- `selected-profiles.json`: the final chosen source profiles, distinct from the measured frozen
  catalogs. Only working contexts and evidence rationales change from the later checked build.
- Source patches, source-file hashes and artifact manifests distinguish the measured builds.
- `validation.json`: final headless check receipt and log hash; `source-files-selected.json`
  identifies the final source and generated catalog after profile selection.
- `controls/`: standalone native Apple token-count probes, rendered Gemma prompt inspection,
  exact native empty-completion replay, and partial native stage logs for the boundary timeouts.
  These contain synthetic benchmark content, not user conversations. The native replay script
  drives the Swift helper; Python handles only bounded process/wire orchestration.

Audit an archive from the repository root:

```sh
python3 -B Benchmarks/Chat/benchmark.py audit \
  --archive docs/reports/data/agent-profiles-2026-11-03/candidate-final.json.gz
```

Reproduce measurements from complete reviewed archives:

```sh
python3 docs/reports/data/agent-profiles-2026-11-03/analyze.py \
  --archives docs/reports/data/agent-profiles-2026-11-03 \
  --output /tmp/agent-profile-measurements.json
```

Integrity audits reproduce recorded evidence; they do not certify task quality. Rubric reviews
are by the implementing agent, not an independent or blinded reviewer. The scenario-order seed
does not seed model sampling. Timings include cold and retained runtimes on one Mac, and failed
turns remain in quality denominators while completed-turn latency excludes them.
