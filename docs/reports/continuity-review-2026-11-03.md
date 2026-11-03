# Continuing Chat: attribution, checkpoint quality and search isolation

This follow-up found a reproducible Apple identity-recovery failure and two application issues:
generated notes were included in developer instructions, and broad conversation searches occupied
the same actor as foreground saves and page reads. The changes correct those application boundaries.
They do **not** make Apple's identity recovery reliable.

All model inputs in this report are synthetic. A user-authorized inspection of an actual conversation
motivated the investigation, but its transcript, personal memories and database are not included here.
The running app, selected model and saved conversations were left unchanged.

## What was tested

Tests ran headlessly on the same 48 GiB M4 Pro with macOS 26.7.2 used for the earlier measurements.
The native controls use production prompts, context admission, tools, storage and provider adapters.
Downloaded inference uses the existing release helper; the test harness is a debug build. Timings below
are individual observations, not release-build first-text benchmarks or lower-memory-device results.

[Evidence](data/continuity-review-2026-11-03/) preserves baseline and experimental traces, the discarded
prompt variants, execution plans, runtime hashes, completion receipts and the timed-out batch.
These controls do not replace the [scored comparison](../local-text-models.md).

## Apple identity recovery

The synthetic conversation distinguishes the human Alex from the companion Pogo. Each condition asks
for the mascot's name, supplies an explicit correction, and asks for the human's name. The five normal
app tools remain available. Memory retrieval returns the correct human attribution.

| Starting context | Baseline | Final context boundary |
| --- | --- | --- |
| Correct history | Distinguishes human and mascot | Distinguishes human and mascot |
| An earlier assistant reply incorrectly calls itself Alex | Repeats the wrong identity and fails to accept the correction; later identifies the human correctly | Still fails mascot identity/correction; later identifies the human correctly |
| The same mistake plus a confused generated summary | Repeats the wrong identity, then says it lacks the information | Still repeats the wrong identity, then says it does not remember |

The delivered latest message and native roles were checked. This is not evidence that the latest
correction was dropped by the UI. It demonstrates unreliable recovery through the current Apple
backend, including its model and framework. It does not isolate a defect in the model weights from
framework behavior.

A shorter instruction set and additional provenance wording did not produce a reliable improvement.
They were discarded. The existing conversation instructions remain; there is no name-specific rule,
response replacement, hidden intent classifier or removal of historical tool results.

The retained change moves generated notes, the original excerpt and retrieved titles out of developer
instructions. They are labeled as fallible source data inside the first retained user entry. Stored
messages remain unchanged. Native role alternation is preserved, including Ministral's strict template.
Changing notes still invalidates native session reuse through exact message comparison.
This follows Apple's guidance to put trusted content in instructions; it is a provenance boundary,
not factual validation. See [Apple's Foundation Models guidance](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models).

## Checkpoint sources and summary quality

The previous summarizer received a rendered dialogue, prior notes and the original opening statement
on every slice. It could continue or copy the dialogue and preserve an assistant's mistaken claim.
The revised prompt receives JSON with explicit human/assistant attribution, prior notes and the next
bounded source page. It requests supported facts and current corrections, and distinguishes questions
and hypotheticals from personal assertions.

The original opening is no longer replayed into each summary request. It is already in the original
archive and first source page; repeating it can privilege stale information. A separate control with
an opening statement exposed repetitive, unsupported Apple notes. Removing that duplicate input
produced the same concise no-facts result as the equivalent source page without an opening.

Apple's final controls correctly produced no-facts notes and the updated deadline. It still copied the
JSON source in the identity-correction case instead of producing a useful summary. The hypothetical
case remained hypothetical but included general weather information. These are quality limitations,
not reasons to declare every nonempty summary correct.

Model-specific semantic observations are recorded in the evidence review. They are a small manual
review of explicit synthetic sources, not independent human scoring or a new model ranking. No
case-specific output filters were introduced. The full archive, recent verbatim turns and explicit
memory provenance remain available even when a generated note is poor.

| Model | Final source-review observations |
| --- | --- |
| Apple | Correct no-facts results and deadline; copies the source in the identity case. |
| LFM2.5 24B A2B | Correct identity and deadline; one placeholder case infers an unsupported archival claim, and the hypothetical case is over-interpreted. |
| Gemma 4 26B A4B | All five small controls retain the supported facts without the observed attribution/date mistakes. |
| Qwen3.5 4B | Correct identity and hypothetical handling; the deadline note adds unsupported wording suggesting the correction happened on May 11. |

See the [semantic review](data/continuity-review-2026-11-03/summary-review.json) and retained outputs.
In particular, lifecycle success must not hide LFM's interpretation issue or Qwen's extra date claim.
Earlier archive-tool-selection misses remain a separate open quality issue; this pass does not claim
to have resolved every recall failure from the broader corpus.

## Repeated native context rollover

Each control starts with 96 archived messages, adds 64 messages before each of three replies, advances
one real checkpoint after each reply, and opens a fresh repository instance to verify the durable
checkpoint. A reply must leave the checkpoint unchanged: summary work happens separately. This
exercises a changing bounded recent window while a summary backlog remains.

| Model | Three replies and checkpoint boundaries | Reopen durable checkpoint |
| --- | --- | --- |
| Apple | Passed | Passed |
| LFM2.5 24B A2B | Passed | Passed |
| Gemma 4 26B A4B | Passed | Passed |
| Qwen3.5 4B | Passed | Passed |
| Ministral 3 8B | Passed | Passed |

These are lifecycle checks, not assertions that each reply is accurate. They complement the earlier
[100K/1M storage and UI checks](stored-conversation-scale-2026-11-03.md) and
[native checkpoint-preemption controls](long-lived-chat-2026-11-03.md).
They do not simulate months of actual inference or test another Mac's memory pressure.

The initial combined LFM rollover-plus-summary batch hit its 120-second process deadline after all
three rollovers and three summary outputs. That partial run is retained as a timeout. The subsequent
plan separates rollover and summary checks into independently bounded phases; it does not silently
turn the timed-out batch into a pass.

## Foreground work during a million-message search

`ConversationSearchWorker` owns a separate read-only SQLite connection. The writer actor remains
available for messages, checkpoints and bounded page reads. SQLite's progress callback checks task
cancellation during the query. The handler is scoped to reads and removed on success or failure, so
it cannot interrupt a later rollback. Clearing history invalidates pending search snapshots.

With a broad query still executing against the retained one-million-message synthetic database:

| Operation | Observed time |
| --- | ---: |
| Save a new message and read the latest page | 15.38 ms |
| Cancel the executing search and join it | 20.01 ms |

The test verified that the broad search was still running when the foreground operations completed,
and that the reader could execute another search after cancellation. A separate SQLite regression
cancels a recursive query after its first row and verifies that the callback is removed even while the
owning Swift task remains cancelled. Normal regressions also verify newly committed messages and
Clear are visible through an already-open reader.

This improves isolation and cancellation, not the ranking algorithm's total execution time. These
observations do not establish a universal latency bound under disk stalls or database lock contention.

## Repository validation

The full check passed with Xcode explicitly selected for the command: 690 selected native tests
across 18 runs, 92 Python tests, architecture/lint, localization, synthetic benchmark fixtures,
inference-helper GPU/protocol checks, helper parent-exit checks and catalog validation.
The initial attempt passed the native tests but localization extraction picked the Command Line Tools
SDK, which could not load `FoundationModelsMacros`. The complete rerun used
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; the system's toolchain selection was not
changed. Both logs and the [validation receipt](data/continuity-review-2026-11-03/validation.json)
are retained. Tests remained headless; the running application was not restarted or replaced.

## Reproduce

Routine behavior and boundary regressions run under `make check`. Native quality controls are opt-in
and print their inputs/outputs for review; a successful test receipt verifies lifecycle and delivery,
not the semantic quality of each answer.

```sh
SILLIES_ATTRIBUTION_CHECK=1 bash scripts/test.sh \
  --filter nativeConversationAttribution --timeout 120

SILLIES_CONTINUITY_MODEL=apple SILLIES_SUMMARY_QUALITY_CHECK=1 \
  bash scripts/test.sh --filter nativeCheckpointSummaryProvenance --timeout 120

SILLIES_CONTINUITY_MODEL=apple SILLIES_ROLLOVER_CHECK=1 \
  bash scripts/test.sh --filter nativeRepeatedCheckpointRollover --timeout 120
```

For an already-installed downloadable model, set `SILLIES_CONTINUITY_MODEL` to its catalog ID,
`SILLIES_CONTINUITY_MODEL_ROOT` to the model-store directory and `SILLIES_CONTINUITY_HELPER` to the
packaged native helper. These tests never download models or open the user's conversation store.
Keep expensive phases separate and do not build concurrently with timing observations.

The opt-in `broadConversationSearchYieldsToWritesAndCancellation` test accepts
`SILLIES_STORED_HISTORY_DIRECTORY` pointing to a synthetic million-message fixture made by
`scripts/check-conversation-scale.py --keep-databases`. Never point it at a user's data.
