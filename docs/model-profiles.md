# Model profiles and agent budgets

Sillies uses one conversation engine with explicit settings for each downloaded checkpoint.
The editable profiles live in [ModelProfiles/Text](../ModelProfiles/Text). The catalog generator
embeds them in each model manifest. Algorithms consume the profile, never a model-name switch.

## What belongs in a profile

| Setting | Meaning |
| --- | --- |
| `context.maximumTokens` | Capacity declared by the pinned checkpoint's text configuration. It does not certify that the full capacity is practical on a particular Mac. |
| `context.workingTokens` | Application working context, bounded by the checkpoint capacity. Its rationale distinguishes measured choices from retained baseline settings. |
| `prefill.chunkTokens` | `null` delegates to the native runtime's model-selected default. An integer is a reviewed override, not a new global default. |
| `runtime.conversationCache` | `disabled` by default. `nativeSession` delegates exact-history continuation to the SDK. `prefixSnapshot` retains one immutable native prefix for an explicitly validated checkpoint. |
| `runtime.prefixSnapshot` | Required only for `prefixSnapshot`: maximum retained tokens and logical state-array bytes. These do not replace the helper's total allocation budget or full-prompt context admission. |
| `runtime.chatTemplate` | `checkpoint` uses downloaded metadata. A reviewed adapter policy can select an unchanged, pinned publisher template shipped with attribution; it never rewrites downloaded files. |
| `generation.conversation`, `summary`, `precise` | Task-specific answer and reasoning allowances, sampling, and repetition context. |
| `conversation.safetyTokens` | Margin for provider framing and boundary measurement. |
| `conversation.compaction` | Summary word target and space to leave after compaction for subsequent messages. |
| `conversation.tools` | Calls per turn, total reserved evidence capacity, and maximum capacity for an individual result. |
| `conversation.history.recent` | Maximum messages and encoded bytes loaded for one reply, independent of archive length. |
| `conversation.history.checkpoint` | Maximum source page and minimum batch size for a background checkpoint slice. |
| `evidence` | Checkpoint sources, pinned runtime revision, and the rationale distinguishing documented requirements from application choices. |

The [official MLX prefill contract](https://github.com/ml-explore/mlx-swift-lm/blob/3b339ad6e3b3f44c8121ecff5131c7fd55e075e6/Libraries/MLXLMCommon/PrefillParameters.swift)
lets models select their defaults when the chunk size is unset. The generic path uses 512; other
implementations can select a different value or apply a model-specific ceiling. Sillies preserves
that behavior instead of forcing 64 across all models.

Foundation Models exposes its context size through the system runtime and owns native prefill and
tool decoding. `AppleConversationPolicy` specifies the application allowances it actually supports;
MLX-specific knobs are not presented as Apple capabilities.

The [November 3 comparison](reports/agent-profiles-2026-11-03.md) selects 8K for LFM 24B and Gemma
12B, keeps 4K for Gemma 26B because compacted follow-ups are faster, and retains the other checkpoints'
baseline contexts. Those measurements preceded the bounded foreground and background checkpoint
implementation described below. Historical scores are not rerun results for this implementation.

## Ownership and validation

- Core holds pure, serializable profile values. The catalog owns checkpoint selection and provenance.
- The app's selected backend supplies conversation policy and generation settings explicitly.
- Reasoning owns token measurement, compaction and bounded tool orchestration.
- The native helper translates the selected profile into SDK parameters. Admission and generation
  use the same task-specific reasoning allowance.
- The model registry invalidates a prepared runtime when its profile changes, even if the weights
  have the same revision. Machine-wide inference admission and memory limits remain in force.

Profiles are required. Invalid capacities, sampling, chunk sizes and overflowing allowances fail
validation before inference. The catalog's offline tests compare generated descriptors with their
source profiles and reject stale runtime provenance. Byte limits protect transport and persistence;
they are not substitutes for token-based context accounting.

Gemma 26B and LFM 24B enable the snapshot path after the [November 4 readiness checks](reports/model-readiness-2026-11-04.md).
Each retains at most 2,048 tokens, with logical state limits of 384 MiB and 128 MiB respectively.
The [controlled cache comparison](reports/cache-isolation-2026-11-04.md) also qualifies Qwen 3.5
2B and 4B, and LFM 2.5 2.6B: 2,048 tokens with 96, 192 and 64 MiB limits respectively.
Session identity and the retained token prefix must match. Changed instructions, tools or history
inside that prefix rebuild it; later differences are processed normally. Every use clones the snapshot; generation never
advances the retained original or rewinds recurrent state. Native state without a copy/size contract
is passed to the current generation but never retained. Failures clear the snapshot, and cancellation
drains generation before state is released. Sampling penalties still see the complete input.

Preparing the first snapshot adds latency. Native balanced prefill also makes different chunk shapes
numerically different, so state-copy correctness alone does not establish answer quality.
Qwen 9B remains disabled because its whole-task review missed the acceptance margin. Native state
replay matched; this is not evidence of state corruption or a conclusion about all Qwen models.
Adding a model requires native state, lifecycle, bounded-memory and conversation/tool comparisons,
not a family-name assumption.

## Long-lived conversations

The complete transcript lives in SQLite. The UI and the model each load bounded pages; neither
needs the entire archive in memory. `ConversationHistoryPreparation` reads one fresh checkpoint
and one page ending at the submitted message. It never walks the unsummarized backlog.

`ConversationContextManager` can only access `ConversationBudgeting`, a measurement capability
without a generation method. It measures the complete request, including instructions, tools and
output allowances, then selects a fitting suffix of complete turns. A reply generates no summaries.
The checkpoint cursor tracks summary progress; it does not evict recent verbatim messages that fit.
If the saved memory prevents even the latest question from fitting, that request omits the memory;
the durable checkpoint remains intact. An individually oversized question returns a recoverable
context-limit error. A missing or reset conversation handle is also reported, never silently replaced.

The prompt identifies partial history and directs the model to `search_conversation` for missing
earlier statements, shared plans and decisions. Saved personal memories remain available through their existing tools. Searchable
originals, not a lossy summary alone, provide continuity. Models can still choose poor searches or
misinterpret evidence; bounded context is not a guarantee of perfect recall.

### Background checkpoint ownership

`ConversationCheckpointMaintenance` owns one coalescing producer for all companions. It queues
only conversation IDs, generations and a source boundary, with a maximum of 16 pending conversations.
After a two-second idle delay, each slice reads one profile-bounded page and generates at most one
summary. A successful slice can schedule another; it never summarizes the backlog in a foreground
reply. The current user turn and unfinished source turns stay outside the checkpoint.

The shared turn gate cancels a running checkpoint when interactive inference arrives, joins its
cancellation, and admits the interactive request first. Slices have a 30-second deadline and stop
with their explicit Chat lifetime, including pause, exclusion and termination. Errors do not advance
the cursor or substitute transcript excerpts for a successful summary. A failed slice waits for later
conversation activity; it does not spin or repeatedly retry while idle.

Checkpoint writes compare the source generation and revision before advancing. Edits, deletions,
resets and competing saves invalidate stale work. UI saves preserve the current persisted checkpoint
rather than overwriting it from an older view snapshot. Each successful write survives a restart;
an interrupted slice resumes from the last committed original-message cursor.

Native MLX decoding enforces a combined generation cap, not separate hard channel caps. Unused
reasoning allowance can become answer text. Reply and checkpoint admission therefore
reserve the combined allowance; they do not assume that an answer-only quota limits visible output.

Each downloaded profile currently declares a conservative recent window of 64 messages / 32 KiB
and checkpoint slices of 24 messages / 12 KiB, eligible at 12 messages or when the page reaches its
byte limit. The byte condition prevents long messages from starving checkpoint progress merely
because fewer than 12 fit in a page. These are application limits,
not published model context capacities or claims of optimal tuning. Actual token measurement can
select fewer complete turns. A single persisted row can exceed the page byte target (up to the
storage row limit), ensuring cursor progress; model admission still enforces its own byte/token limits.

## Tool evidence

The record ID selects a document. Passage ranking gives requested details precedence over words
already identifying its title. Compound questions can return separate passages, each with its own
coverage and continuation offset. These are lexical matches, not a semantic-search guarantee.

Tools provide complete full and compact representations. Downloaded backends measure them, and
the toolbox chooses a representation within the result and remaining turn allowances. It never
clips serialized JSON. A completed operation whose output cannot fit is reported as such, not as
an operation that never ran. Cached calls prevent repeating writes during context recovery.
Recovery can replay cached evidence, but it cannot acquire a second allowance for new operations.
The execution quota belongs to the entire user turn, including its recovery attempt.

Downloaded models also revalidate each native tool round, including its ephemeral reasoning state.
Foundation Models owns its internal tool loop. Its backend explicitly selects provider-managed
result admission: structured byte bounds, the call limit and one existing context-recovery attempt
remain active. Tokenizing results during an active Apple tool turn added continuation latency in
a native control, so this backend does not retokenize between tool execution and continuation.
Initial request measurement and compaction still use Apple’s tokenizer. Its private transcript is
never rewritten to simulate control that the SDK does not expose.

A downloaded model can finish with an empty native completion after a tool call if it already
delivered its reply before calling the tool. Transport accepts that verified completion and lets
the conversation owner preserve the earlier text. Empty initial replies, missing completion
signals and truncated generations remain errors; this is protocol handling, not an output filter.

## Evaluating changes

Run `make check` and the focused profile, compaction, evidence and retrieval regressions. Then freeze
baseline and candidate executables and catalogs for bounded native runs. Compare identical cases,
retain failed and timed-out turns, and inspect actual persisted memory decisions. Separately report
quality, latency distribution, summary work, tool calls and memory; a faster incorrect reply is a failure.

Benchmark metadata includes the resolved profile. MLX generations report the helper lifetime's peak
active device allocations; this is not whole-process RSS, and Apple does not expose that MLX metric.
One machine's measurements do not establish performance on every supported Mac. Existing published
leaderboards remain historical until a separately reviewed comparison replaces them.
