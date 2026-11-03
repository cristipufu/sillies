# Channel framing and model-specific memory decisions

The retained change prevents malformed native reasoning-channel markers from reaching Chat text,
storage or speech. It adds one bounded recovery attempt before any text is delivered, reusing only
completed tool operations. The memory/source-selection experiments did not establish a reliable
improvement and are not enabled in the app. No shared prompt or model profile was changed.

## Gemma streaming: reproduced and fixed

The earlier failure returned `<|channel>` immediately before an otherwise correct archive answer.
Google documents this as a standalone control token followed by a channel name such as `thought`.
The pinned MLX Swift LM parser recognizes the complete thought opener, allowing a bare or unknown
opener to emerge as response text. This is an integration boundary defect regardless of why the
model produced that sequence. See [Gemma's format](https://ai.google.dev/gemma/docs/core/prompt-formatting-gemma4)
and [thinking guidance](https://ai.google.dev/gemma/docs/capabilities/thinking).

The installed template already supplies the documented empty-thought primer for a new reply.
Inspection of the actual initial request and tool continuation found 2,106 and 2,317 input tokens;
the continuation ends at the inline tool-response boundary. It is not a second user turn. We did
not append a speculative assistant opener or discard the model's required tool-turn reasoning.

`MLXReasoningChannel` now validates both reserved open and close markers after native channel
parsing. Gemma's bare opener is included independently of its channel label. Other providers use
their declared delimiters, and plain-text providers remain unchanged. Partial delimiters are held
across chunks. A complete invalid marker produces a typed failure, including at end-of-stream.
The decoded-text parser still cannot distinguish an intentionally quoted reserved marker from an
actual native control token; this change does not claim token-level fidelity.

`LocalConversationService` can recover once from that typed failure before the first text delta.
`ConversationToolbox` then permits only exact cached operations, comparing normalized JSON arguments
independently of call IDs. Changed arguments receive an explicit `notExecuted` result. A retry cannot
make a second memory write. Cancellation, output limits and failures after published text do not
restart the reply. A second failure propagates normally; this is not an error-free-generation claim.

| Native control, Gemma 4 12B | Clean reviewed answers | Observed marker leaks |
| --- | --- | --- |
| Frozen baseline, three repetitions | 2/3 | 1/3 |
| Parser/recovery candidate, three repetitions | 3/3 | 0/3 |

All six answers retrieved the correct fact; lexical checks alone incorrectly passed the leaked
baseline reply. No candidate repetition emitted the malformed sequence, so these native runs do not
demonstrate a real-model retry. Deterministic collector tests replay the observed malformed output,
unknown labels, bare openers and orphaned closers at every two-chunk split and one character at a
time. Injected-backend tests exercise recovery, persistent failure, published text, cancellation,
token limits, changed arguments and cached writes. Three native repetitions are not a reliability
estimate or a latency comparison.

## Completed memory/source investigation

The six-case, seven-turn evaluation uses the previously frozen outcome-only worker corresponding
to the reasoning code in `8f9f122`. Existing completed cases were not rerun. Gemma 12B and the last
LFM 24B case were completed; the operator interruption remains explicit. The interrupted case was
also replayed separately, without replacing the original receipt.

| Model | Reviewed task passes out of six | Remaining observations |
| --- | --- | --- |
| Gemma 4 26B A4B | 5 | Missed saving a preference alongside a general question |
| Gemma 4 12B | 4 | Missed that preference; rewrote a birthday's provenance after a question |
| LFM2.5 24B A2B | 3 | Two failures and one operator interruption; the separate replay searched outside the requested chat source |
| LFM2.5 2.6B | 1 confirmed | Four failures; one historical claim remains unresolved in review |
| Apple | 1 | Missed saves, source confusion and unnecessary private searches |

These are difficult diagnostic cases, not updated leaderboard scores. Gemma 12B's answer identifying
the quoted speaker as Ivo passes semantic review even though the narrow `narrator/character` lexical
check fails. Conversely, repeating the correct birthday while overwriting its source with a question
fails the persistence requirement. The frozen expectations have not been edited to improve scores.

## Experiments rejected

The prompt-only candidate strengthened automatic saving and explicit source restrictions. It used
the same frozen cases, native helper, model profiles and evaluator. The planning candidate added a
separate native structured classification call and filtered available tools; it was enabled only
for Apple, leaving other profiles on direct tool calling.

| Candidate | Apple | LFM 24B | Gemma 12B | Decision |
| --- | --- | --- | --- | --- |
| Stronger automatic-save/source instructions | 1/6 | 4/6 | 3/6 | Reject the shared change: mixed results and an incorrect write during an opt-out |
| Apple-only intent planning | 1/6 | Not tested | Not tested | Reject: incorrect classifications and missed saves |

The favorable LFM source-restriction result is a single observation, not evidence to enable a
model-specific rewrite. A controlled repeated comparison separating the two instruction changes
would be needed to establish that choice. One Gemma correction failed with native
`rejectedToolCall/malformedSyntax`; the receipt lacks the rejected token sequence, so generation
versus parsing remains unresolved. It is counted as a failed task, not asserted to be a model defect.

Apple's valid planner returned `earlierChat/unchanged` for all seven turns, including general
questions and explicit names. Median classification time was **456 ms**, range **440–1,059 ms**.
This is the extra stage's duration, not a measured increase in total reply latency: filtering tools
also changes downstream work. The classifier did not justify that stage or the missed capabilities.

Native FoundationModels probes outside the app checked direct message input, a smaller enum schema,
reordered enum cases and generic examples. Reordering did not resolve the bias. Examples corrected
the birthday-question classification but still labeled an explicit opt-out as a new fact. These
probes reject these configurations; they do not prove that every possible Apple classifier fails.

The first planning experiment was invalid: the benchmark decorator failed to forward the new tool
scope, leaving every capability unrestricted, and counted classification as compaction. Its raw
receipts are retained and explicitly excluded. The subsequent run forwards the scope and records
preparation generations separately. None of this experimental classifier infrastructure is retained
in production.

The architectural rule is **shared orchestration, model-specific measured strategy**. Existing
context, sampling and native protocol profiles remain in force. An extra planning call should only
be enabled for a selected profile after showing a useful correctness/latency trade-off on that model.
These results do not justify keyword routing, special-case answer filters, a global classifier or
claiming that automatic memory decisions are solved.

## Validation and evidence

All native evaluations used synthetic temporary stores, release workers and installed models on one
M4 Pro with 48 GiB and macOS 26.7.2. They did not read user conversations, change the selected model,
restart the running app or open windows. Reviews were performed by the implementing agent against
replies, calls and persisted state, bound to evidence hashes; independent review remains outstanding.

The [validation receipt](data/channel-memory-followup-2026-11-03/validation.json) records the final
headless checks. The native candidate worker was frozen before the final explicit cancellation check
at recovery entry; that additional check is covered by the final build/tests. All seven exported
archives passed evidence audits. Audits reproduce receipts and checks; they do not certify semantic
quality. The main model-selection table is unchanged.

- [Resumed evaluation](data/channel-memory-followup-2026-11-03/heldout-resumed.json.gz), [audit](data/channel-memory-followup-2026-11-03/heldout-resumed-audit/audit.json).
- [Separate interrupted-case replay](data/channel-memory-followup-2026-11-03/interrupted-replay.json.gz), [audit](data/channel-memory-followup-2026-11-03/interrupted-replay-audit/audit.json).
- [Prompt-only experiment](data/channel-memory-followup-2026-11-03/instruction-candidate.json.gz), [audit](data/channel-memory-followup-2026-11-03/instruction-candidate-audit/audit.json).
- [Valid Apple planning experiment](data/channel-memory-followup-2026-11-03/intent-scoped.json.gz), [audit](data/channel-memory-followup-2026-11-03/intent-scoped-audit/audit.json).
- [Invalid first planning run](data/channel-memory-followup-2026-11-03/intent-candidate.json.gz), [exclusion reason](data/channel-memory-followup-2026-11-03/invalid-intent-experiment.json).
- [Channel baseline](data/channel-memory-followup-2026-11-03/channel-baseline.json.gz), [audit](data/channel-memory-followup-2026-11-03/channel-baseline-audit/audit.json).
- [Channel candidate](data/channel-memory-followup-2026-11-03/channel-candidate.json.gz), [audit](data/channel-memory-followup-2026-11-03/channel-candidate-audit/audit.json).
- [Experiment sources and native classifier probes](data/channel-memory-followup-2026-11-03/experiment-sources.json.gz), [rendered-template inspection](data/channel-memory-followup-2026-11-03/gemma-template-inspection.json.gz).
