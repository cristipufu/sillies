# Qualify local runtime changes

A faster synthetic answer is a reason to investigate, not enough evidence to change everyone's
model settings. Sillies keeps production adapters, model profiles, experiments and qualification
records separate. Inference remains in the existing isolated helpers.

## Shipping profiles

[The qualification matrix](../../ModelProfiles/runtime-qualifications.json) binds each catalog
checkpoint to its complete profile, native dependency revisions, cache ownership and reviewed
reports. It records held optimizations as well as enabled ones. `make check` rejects missing rows,
changed profiles/dependencies and changed evidence. Required tool-protocol, private-channel,
cancellation, cache-ownership and profile-invalidation checks remain executable regressions.

The matrix preserves the scope and limits of earlier experiments. It is neither a new leaderboard
nor proof that every input works. When changing a runtime or enabling an optimization, investigate
failures, run bounded native controls and production workflows, review the evidence, and update the
record deliberately. A file hash establishes identity, not scientific validity.

## Prefill on a particular Mac

The benchmark accepts `--prefill-tokens N`. It changes only the processing batch in a copy of the
selected model's profile. The live app, downloaded files, context budgets and decoding settings stay
under their existing owners. Apple manages its own prefill and does not accept this experiment.

Use a frozen release worker/helper and the same corpus, machine and deadlines for both arms:

```sh
python3 Benchmarks/Chat/benchmark.py run --models qwen-3.5-4b \
  --corpus /path/to/synthetic-corpus --worker /path/to/ChatModelBenchmark \
  --helper /path/to/SilliesTextInference.app/Contents/MacOS/SilliesTextInference \
  --output build/prefill/control --repeats 2 --max-seconds 120

# Repeat the command with --output build/prefill/candidate --prefill-tokens 1024.
# Resume identical commands in bounded batches; alternate which arm runs first.
```

Set the experiment's candidate count and total time limit before running it. Use at least six
production-tool scenarios covering identity, memories, Vault and mixed knowledge, with two repeats.
Retain failed and timed-out cases. Record complete, evidence-bound rubric reviews in each run's
`reviews.json`; uncertain or unreviewed answers cannot qualify a setting. Inspect changed answers,
not just aggregate scores. Include cold/warm distribution and device memory in the report.

```sh
python3 Benchmarks/Chat/qualify-prefill.py build/prefill/control build/prefill/candidate \
  qwen-3.5-4b build/prefill/qualified.json
```

Qualification requires identical conditions, complete coverage, no new objective or reviewed
failure, and at least a 10% median first-text improvement. This is a conservative bounded screening
policy, not a statistical claim of universal equivalence. A candidate cannot compensate for a new
miss with an unrelated improvement. Runtime identity includes the checkpoint, base profile, helper
binary digest, processor, memory and OS. No host name or serial number is collected.

Applying a qualified result is explicit:

```sh
SILLIES_TEXT_HELPER=/path/to/app/SilliesTextInference.app/Contents/MacOS/SilliesTextInference \
  /path/to/TextModelBenchmark apply-calibration build/prefill/qualified.json \
  "$HOME/Library/Application Support/Sillies/TextModels"
```

The receipt is written atomically under `TextModels/Calibration/<model-id>.json`. App composition
resolves it before preparing the backend. The registry's existing profile identity forces a fresh
runtime when it changes. Invalid, stale, oversized or unreadable receipts leave catalog defaults
in use and log the failure. Delete the receipt to restore defaults. There is no automatic tuning
job or inference during Settings rendering.

## Portable benchmark reports

```sh
python3 Benchmarks/Chat/benchmark.py share --output build/prefill/control \
  --archive build/prefill/hardware-report.json
```

This recomputes and validates evidence, then exports an allowlist of hardware metadata, checkpoint
identities, runtime/corpus hashes, coverage, errors, latency and separate automatic/review counts.
It excludes prompts, replies, tool arguments/results, local paths and reviewer identities. Nothing
is uploaded. Review the file before voluntarily attaching it to an issue or contribution. Full raw
evidence remains local; the portable summary does not substitute for reviewing that evidence.
