# Readiness study evidence

Read the [report](../../model-readiness-2026-11-04.md) and
[registered limits](../../../../Benchmarks/Chat/experiments/model-readiness-2026-11-04/study.json)
before interpreting scores. All chat, Vault and memory content is synthetic.

| Files | Contents |
| --- | --- |
| `prefix-workflow-baseline-*.json.gz` | Frozen production baseline: six cases / seven turns per checkpoint. |
| `prefix-workflow-prefix-*.json.gz` | First candidate, including the discovered empty-versus-absent tool-schema bug. Do not label these corrected results. |
| `prefix-corrected-workflow-prefix-*.json.gz` | Fresh runs after the shared tool-schema contract fix. |
| `retrieval-archived-*.json.gz` | Corrected semantic/keyword comparisons: source messages are outside recent context, with initial-prompt absence checks. |
| `invalid-retrieval-*.json.gz` | Context-contaminated comparisons, preserved and excluded. One interrupted schedule has pending cases; none are silently counted as successes. |
| `split-*.json.gz` | Rejected separate create/correct tool candidate; full-rubric reviews include persisted state. |
| `*-audit.json` | Recomputed automatic checks, primary metrics and evidence-bound review totals. |
| `native-probes.json.gz` | Raw supervised batch logs: matched latency, state, lifecycle, capacity, model replacement, embeddings and failures. |
| `experiment-inputs.json.gz` | Frozen requests, embedding vectors/artifacts, fixture amendments, baseline overlay and derived metrics. |
| `experiment-sources.json.gz` | Temporary native embedding and split-tool adapters plus bounded supervisors/probes. Not production code. |
| `final-source-overlay.json.gz` | Changed Swift/Python/JSON source content needed alongside the baseline commit. |
| `binary-hashes.json.gz` | Frozen native helper and benchmark binary identities. |
| `metrics.json.gz` | Small derived warm/cold/retrieval summaries; raw receipts remain authoritative. |
| `execution-ledger.json` | Batch commands, deadlines, status, log hashes and cumulative execution time. |
| `repository-check-*.log.gz` | Complete repository check output before and after the tool-contract fix. |
| `SHA256SUMS` | Integrity hashes for this directory, excluding the checksum file itself. |

To verify one comparison from the repository root:

```sh
python3 -B Benchmarks/Chat/benchmark.py audit \
  --archive docs/reports/data/model-readiness-2026-11-04/prefix-corrected-workflow-prefix-lfm-2.5-24b-a2b.json.gz
```

The auditor checks integrity; it is not an independent semantic judge. Manual reviews identify their
author and scope, bind to the full recorded evidence and preserve uncertain outcomes. Raw absence of
an incorrect word is not proof of a correct answer. The retrieval corpora's expected identities and
rubrics are kept outside inference inputs.

Native timings are not a full-corpus leaderboard or a whole-app latency guarantee. Initial
preparation, repeated warm prefixes, generation duration, streaming delivery and TTS are different
measurements. The native state probe's original `bytes` field measures the live cache after its suffix,
not retained snapshot bytes; the diagnostic now names it `liveStateBytes`. Capacity probes separately
record the actual retained logical state and MLX active/peak allocations, not process RSS.

Reproduction needs the pinned model artifacts and bundled helper kernels. Experiment sources retain
their isolated scratch paths; adapt those paths when recreating a run, freeze new provenance, and do
not resume an old result directory with changed binaries, resources or evaluator code. Never point
these fixtures at a real conversation database or Vault.

The final cache implementation and the experimental adapters are preserved as source. Not every
intermediate helper diagnostic dispatcher/refactor was captured verbatim. Binary hashes identify
the exact earlier executables, but do not claim a bit-for-bit source reconstruction of each exploratory
helper. Rebuild the reviewed implementation and recorded fixtures as a new, separately frozen run.
