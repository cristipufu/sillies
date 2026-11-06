# Apple context representation follow-up

This follows [explicit Vault context and memory controls](conversation-context-2026-11-06.md).
The controls compare the implementation under review on 6 November 2026, not the older published
benchmark. The experiment's source hashes are retained with its results.

## Frozen questions and stop conditions

Eight synthetic cases are frozen in `NativeRepresentationCase.swift`: arithmetic, general
knowledge, a selected note, the human's pinned name, the companion's identity, mixed general/private
questions, an explicit memory save, and an explicit opt-out. Each case uses fresh persisted state.
The app's instructions, tool definitions, tools, streaming adapter, output allowance and memory
repository are used. No user's archive or conversation is read by these controls.

| Variant | Difference from the control |
| --- | --- |
| Baseline | Current implementation, including the new selected-record and pinned-fact context. |
| Structured tools | Parse JSON tool results into Apple's `GeneratedContent`; preserve plain-text outcomes as strings. Calls, arguments and persisted exchanges remain unchanged. |
| Entity background | Encode selected records and pinned facts as quoted JSON data, with each fact explicitly attributed to the human. Keep developer instructions and original message roles unchanged. |
| Combined | Run only if an individual representation shows a useful improvement. |

The initial scan runs each of the first three variants once. A promising variant must repeat its
gain against a fresh baseline, then pass fresh follow-up cases before production integration. The
maximum is 72 native requests in this investigation; each execution batch has a 90-second external
watchdog. Stop when no candidate qualifies or that budget is exhausted. Do not keep rewriting the
same prompt around observed answers.

Qualification requires at least two additional successful tasks out of eight in both paired runs,
correct human/companion identity, no opt-out writes or invented private evidence, and median response
latency no more than 20% above the paired control. Full application continuation, restoration,
cancellation and context admission must then be checked before enabling a candidate. A test passing
only means observations completed; answer quality requires reviewing replies, calls and actual
persisted state. These small diagnostic controls cannot replace the published model leaderboard.

## Documentation checked

Apple [supports both strings and structured tool outputs](https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling).
The current string representation is therefore valid; this is an experiment, not a claimed API fix.
[Tool schemas must remain included](https://developer.apple.com/documentation/foundationmodels/tool/includesschemaininstructions)
for tools the model was not trained to know. The newer explicit tool-calling controls require macOS
27 and cannot solve behavior on the tested macOS 26.7.2 installation.

## Results

**Neither candidate qualified.** The initial scan completed 24 requests. Both candidates still
confused the human's identity with the companion's and persisted a fact despite an explicit opt-out.
The combined arm, repeat qualification and fresh follow-ups were not run: the required identity
and write-decision checks already failed. No representation change is enabled in the product.

| Case | Current implementation | Structured tool outputs | Entity-attributed background |
| --- | --- | --- | --- |
| 12 × 9 | Failed after private searches. | Repeated the question without answering. | Failed after private searches. |
| Why the sky is blue | Declined after private searches. | Claimed missing private evidence. | Correct explanation, but unnecessary searches. This case has no background, so its input was unchanged. |
| Selected Cedar note | Correct Friday 09:15; three unrelated save attempts, all rejected. | Correct Friday 09:15; no save attempt, but an unrelated conversation search. | Claimed the supplied note was unavailable. |
| Human's pinned name | “My preferred name is Mira”; persisted a learned name from a question. | Same identity error and unintended write. | Failed to use the supplied name; no write. |
| Companion's name | Called itself Mira. | Called itself Mira. | Called itself Mira. |
| Lisbon + selected Cedar note | Native tool allowance exhausted; no completed answer. | Claimed neither fact was available. | Both facts correct, after four unnecessary private searches. |
| Explicit jasmine memory | Persisted and acknowledged. | Persisted; reply restated the fact without explicitly acknowledging the save. | Persisted and acknowledged. |
| Explicit mango opt-out | Persisted mango and claimed to save it. | Persisted mango and claimed to save it. | Persisted mango and claimed to save it. |

Correct answer text and correct actions are reviewed separately. In particular, the selected-note
answer is not a clean task success when it attempts unrelated memory writes. Rejected attempts are
distinct from actual writes: the name question and mango opt-out changed persisted state, while the
baseline selected-note and companion-name save attempts did not. These are integration observations,
not evidence that every possible prompt or future system model must fail.

| Variant | Median first text | Median native request duration | Completed native requests |
| --- | --- | --- | --- |
| Current implementation | 3.52 s | 4.02 s | 7/8 |
| Structured tool outputs | 3.49 s | 3.73 s | 8/8 |
| Entity-attributed background | 3.76 s | 4.15 s | 8/8 |

One pass per arm is insufficient to claim a speed improvement. Duration starts after context
preparation/admission and includes native generation and its tool calls; it ends on completion or
failure. First text is not necessarily a substantive answer. TTS, model-independent UI work and
full application recovery are not measured here. The native tool-budget failure is recorded at this
boundary; this probe does not exercise the application's outer recovery path.
The baseline first-text median has seven samples because its failed request emitted no text;
the two candidate medians have eight. This missing observation is not assigned a zero latency.

## Evidence and evaluation review

Raw requests, replies, exchanges, actual persisted facts, timings and completion receipts are in
[the evidence directory](data/native-context-representation-2026-11-06/). The
[manual review ledger](data/native-context-representation-2026-11-06/review.json) covers all 24 cases;
[provenance](data/native-context-representation-2026-11-06/provenance.json) includes source snapshots,
hashes, build identity and run order. None of these results uses the user's conversations or Vault.

- Each case has a separate conversation owner, an empty learned-memory store at the start, and
  access to the same single synthetic Vault note. Pinned facts are supplied only in their declared
  cases. Storage is temporary and removed after each variant.
- All six app tools remain registered. Definitions, instructions, message roles, native streaming,
  admission, four-call execution allowance and 240-token output allowance remain in use. Inputs
  occupied 1,868–2,167 tokens and passed the actual 4,096-token context admission check.
- Canonical request comparisons exclude internal conversation/context identifiers. Structured-tool
  requests match the baseline in all eight cases. The entity arm changes only the four cases with
  supplied background. Its better sky answer therefore cannot be credited to the new representation.
- The entity arm changes JSON shape, field order and subject attribution together. It does not
  isolate subject attribution alone. Native tool-result JSON ordering and generation variability
  are not controlled; this is a diagnostic scan, not a deterministic performance comparison.
- The runner's success means that observations were collected and temporary state was cleaned up.
  It does not award quality passes. Review includes the full exchanges and persisted facts, not
  keyword presence or the model's verbal claims. The implementing agent performed this review;
  independent human review has not occurred.
- Runs used macOS 26.7.2 on the 48 GiB M4 Pro, with the app sources under review and debug
  test binaries. Apple does not expose the downloaded system-model asset version. These runs are
  not directly comparable to the release-build leaderboard, which remains unchanged.

The diagnostic harness remains opt-in under `SILLIES_NATIVE_REPRESENTATION`; ordinary tests do not
invoke the model. Its variants are confined to the test target. The only native adapter change is
an initializer accepting a session so the experiment reuses production streaming and cancellation
handling. There is no production experiment selector, extra inference stage or output filter.

At the end of this experiment, `make check BUILD_DIR=build/context-validation` passed with
896 selected Swift tests across 20 runs, 112 Python tests and all packaged-helper, architecture,
localization and fixture checks.
Its completion receipt is `build/test-results/run-3cf453c0/verified.json`. The opt-in observations
have their three separate receipts in the evidence directory; normal test completion does not
represent another model-quality run. Earlier stress and race checks for the product implementation
are recorded in the [implementation report](conversation-context-2026-11-06.md#validation).

To reproduce one diagnostic arm after `swift build --build-tests`, use the repository toolchain
and checked runner (the output parent directory must already exist):

```sh
source scripts/toolchain.sh
SILLIES_NATIVE_REPRESENTATION=baseline \
SILLIES_NATIVE_REPRESENTATION_OUTPUT=/tmp/sillies-apple-baseline.json \
python3 -B scripts/run-checked-tests.py \
  --bin-path "$(swift build --show-bin-path)" \
  --framework swift-testing \
  --filter nativeRepresentationControlsPreserveAppToolsAndPersistence \
  --skip 'Sillies(?!VaultTests).*' --timeout 90
```

The other executed arms are `structuredTools` and `entityBackground`. Use a separate output file
for each and retain every outcome. This requires Apple Intelligence to be available in English.

## Product decision

Keep the explicit Vault selection and user-owned memory controls, with their independent storage
and lifecycle tests. Keep the existing Apple context representation. The Apple routing/identity
gap and automatic-memory decision failures remain unresolved; supplying correct facts does not
guarantee that this model will use them correctly. The model-selection UI already offers optional
downloads, and the [model guide](../local-text-models.md) reports the broader reviewed comparison.
This investigation neither changes a user's selected model nor silently disables their tools.
