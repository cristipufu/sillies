# Add a local Chat tool

Chat passes native user, assistant, tool-call, and tool-result messages to its selected local model.
A tool is a capability supplied by app composition, not a function name parsed out of generated prose.
The tools search/read Vault records, search earlier conversation messages, look up personal memories,
and save explicit user facts with provenance. They cannot edit/delete Vault records, run commands,
or access the network. Memory removal and Undo are explicit user actions in the interface.

Downloaded providers separate reasoning from visible text before streaming across IPC. Private
reasoning may travel in `TextGenerationOutput.reasoningContent` and `TextMessage.reasoningContent`
only to continue the current tool turn. It is never part of `ChatMessage`, saved tool exchanges,
conversation summaries, or speech. The adapter supplies it to the native chat template as
`reasoning_content`; it excludes it once a new user turn begins. This follows
[Gemma's documented tool-turn exception](https://ai.google.dev/gemma/docs/core/prompt-formatting-gemma4#managing_thought_context_between_turns).

`MLXReasoningChannel` uses the pinned SDK's streaming channel parser and declared model conventions,
with the Gemma 4 channel convention supplied by the adapter. Its decoded-text parser cannot distinguish
a literal quoted protocol delimiter from a real channel boundary; do not claim token-level fidelity
for examples that deliberately quote those reserved delimiters. Native tool framing still belongs to
the SDK. Provider tests must cover split delimiters, primed/truncated reasoning, IPC propagation,
tool-result continuity and removal from subsequent user turns.
An unmatched configured closing delimiter is rejected before that delimiter reaches the text sink,
including when split across chunks. Earlier valid deltas can remain as an interrupted reply; do not
silently replace already displayed or spoken text. This validates protocol framing, not answer truth.

Conversation search excludes the current user message before ranking and limiting results. Vault
search explicitly returns partial excerpts; read a record for details absent from the search result.
Record reads rank bounded, overlapping passages by distinct query-term coverage. They report the
actual character range and total captured-text length, including in shortened recovery results.
The optional `offset` parameter continues at the returned `nextOffset`; omit it for a new query or
use zero to start at the beginning. An invalid offset returns no evidence. A partial passage cannot
establish that an unmentioned detail is absent from the rest of a record.
Memory writes bind provenance to the original current user message in application code. Tool schemas
and prompts express the storage policy, but correct provenance alone does not prove that a model
chose an appropriate fact: evaluate real persisted state, opt-outs and identity separately.

## Add a capability

1. Implement `ConversationTool` in the feature that owns the data. Define a stable name, a concise
   description, typed parameter definitions, localized activity text, and `call(arguments:)`.
   Decode arguments with `ConversationToolArguments.decode` into a small `Decodable` type before
   accessing storage, then validate identifiers and limits at the boundary. The toolbox returns a
   bounded `notExecuted` correction result for argument-decoding failures, preserving the call ID and
   consuming the existing call budget. Storage decoding failures and cancellation must propagate;
   never catch every `DecodingError` around the entire tool body as an invocation mistake.
   Mark optional parameters with `.optional`; Apple and MLX adapters preserve that requirement in
   their native schemas. An omitted optional field must have a defined meaning in the tool decoder.
2. Return `ConversationToolOutput` with bounded source text and an optional shorter `briefText` for
   context recovery. Return `ChatSource` references only for records actually retrieved. Keep full
   record bodies, storage paths, and image bytes out of model context. Empty text and missing records
   are different cases: describe them accurately.
3. Inject the tool through `ReasoningServices.makeConversation(tools:)`. Chat and reasoning depend
   on the capability; they must not import storage or construct live services. Native window actions
   belong in the app's presentation adapter. A returned source card opens the existing Vault.
4. Exercise the tool against temporary storage, including deleted records, malformed arguments,
   large bodies, cancellation, and bounded results. Add an injected-backend test for the native
   call/result exchange and an opt-in short real-model evaluation for its natural-language use.

`ConversationToolbox` owns each turn's allowed names, call budget, cached tool results (including writes), progress, and
source references. Each attempt permits four calls and 12 KB of returned text; one context recovery
attempt may reuse cached results in shorter form. Arguments are capped at 2 KB. Model-produced query
syntax never becomes SQL. Vault search quotes literal keywords, ranks matching terms through FTS,
and returns at most five records. Screenshot search uses indexed OCR and metadata, not image vision.
Search output distinguishes `returnedRecordCount` from `totalVaultRecords`, which counts the entire
Vault, not a filtered category. Full and brief results preserve both counts. Output encoding is stable.
Cards belong to replies, never a second global progress section. Repeated retrieval preserves evidence
without duplicating cards already displayed in the same conversation.

These limits are resource boundaries, not a way to determine whether a model's answer is true.
After the execution allowance is exhausted, the downloaded-model loop requests an answer without
advertising tools. A further attempted call receives a bounded refusal result and one final completion
attempt. It must never execute an additional operation. Refused calls are not empty search results.
Evaluate prompt and tool design with real examples; do not add word-specific output filters.

## Add a conversation backend

Implement `ConversationBackend` with native roles, tool definitions, `contextWindowTokens`, and
`inputTokenCount`, and `streamConversation`. Forward `reasoningTokenReserve(for:)` through backend
decorators so summary admission matches the native generation allowance. Await the user-facing text
sink; keep tool arguments
and results in native protocol entries rather than the speech stream. Normalize a genuine context overflow to `TextModelError.contextLimit`. Preserve
call IDs and names across assistant requests and tool results. An unsupported native tool format
must report a capability error; it must not simulate execution by inventing results.

Apple uses `LanguageModelSession`, `Transcript`, and `Tool`. The downloaded runtime uses the official
MLX Swift LM message and tool APIs in the isolated helper. `PreparedTextModel.complete` returns text
and native calls; a measurement request tokenizes without generating. Do not flatten a conversation
into one JSON user message or ask the model to print a tool invocation as ordinary text.

Apple conversations with tools use greedy sampling: on macOS 26.7.2, both custom stochastic
sampling and the system default intermittently failed on a first-turn greeting with an internal
token-generation error. This is an adapter policy, not a shared setting for downloaded models.
`AppleGenerationFailure` preserves cancellation and context-overflow recovery, unwraps tool
failures, and translates undocumented engine errors without logging conversation content.
Chat distinguishes reply generation from voice synthesis so recovery opens the appropriate settings.
Real-model checks verify successful replies and retrieved record IDs; they do not guarantee that
Apple avoids unnecessary read-only searches or that every sentence of its prose is accurate.
Apple retains its completed native transcript across turns when our committed history matches,
including tool exchanges. Keep tools registered and rebind execution to the current turn's toolbox.
Do not remove historical tool results merely because a later question is about general knowledge.
There is no intent-classification inference step before the normal reply.

## Context and continuity

Keep developer instructions separate from generated context. `ConversationContextNotes` attaches
bounded, explicitly fallible notes to the first retained user entry; it preserves the existing native
role order and stored originals. This also supports templates such as Ministral's, which require
alternating user/assistant roles. Never put a summary, original user excerpt or retrieved record title
inside developer instructions. Test checkpoint changes against native continuation reuse. Summary
sources retain separate human and assistant attribution; do not treat assistant claims as confirmed
human facts. See the [continuity and attribution investigation](../reports/continuity-review-2026-11-03.md).

`ConversationLibrary` owns the durable SQLite history. `ChatSession` holds at most 128 recent messages
and a persisted `ConversationMemory`; `ConversationBrowser` pages older originals independently.
`ConversationHistoryTools` creates companion-scoped tools per turn from injected repository protocols.
`save_memory` asks for the fact’s key and value. Corrections can also supply the exact `memoryID`
and `revision` returned by `search_memories`. Storage resolves that identity inside the write
transaction, retains its canonical topic key, and rejects stale, deleted or foreign targets. This
prevents a correction that names its target from creating another fact under a different key.
The model still owns the semantic decision to correct a fact rather than create one; IDs do not
prove that decision is appropriate. Evaluate actual resulting memories, including duplicate facts.
The host binds the original current
user message and its ID as provenance, so model capitalization or punctuation cannot break a save.
Memory search returns an explicitly user-attributed envelope, with original excerpts labeled as user
statements. These facts describe the person chatting, not the mascot. The companion's identity comes
from its character profile in the instructions; native user/assistant roles and historical tool results
remain intact.
Storage verifies that the source belongs to this companion and was written by the user; stored receipts
make successful changes visible and undoable. Clear/Forget/Undo rotate the storage generation so late work cannot restore deleted state.
`LocalConversationService` shares the interactive inference gate with other reasoning work.
`ConversationContextManager` measures instructions, history, and tool schemas, then reserves room
for the reply and tool results. Apple uses its tokenizer on macOS 26.4 or later; earlier systems use
an estimate. Downloaded models use the installed tokenizer in the helper.

Reply preparation reads one checkpoint and one bounded recent page. It selects a fitting suffix of
complete turns without summarizing or walking old history. `ConversationCheckpointMaintenance`
prepares older checkpoints separately during idle time; each cancellable slice reads one bounded
page and generates at most one summary. Interactive inference preempts it. Source batches split at
complete user-turn boundaries according to measured token capacity, including the summary task's
reasoning reserve. Generation/revision checks reject stale writes after edits or resets. A short,
attributed opening statement is retained separately; later corrections take precedence. Recent
turns retain native roles and tool exchanges. The summarizer is a separate text task: attributed old turns are source data, not an active
conversation to continue. The summary keeps attributed facts, preferences,
corrections, decisions, and unresolved questions. Record references come from executed tools and
remain separate from generated memory. The original history remains visible and is saved in full;
there is no 100-message stop. History, summaries and personal memories persist per companion and are never shared across mascots.

Summaries are lossy. This is continuity, not perfect recall of every sentence. If summarization
fails, the previous checkpoint and full transcript remain intact. The reply can use recent context,
saved memories and `search_conversation` for older evidence. Cancellation retains an already visible
partial reply, marked as interrupted, together with the
prefix of fully played phrases. Interruption metadata belongs in instructions, not annotations appended
to assistant speech in model history. A context overflow before text delivery triggers one retry
with minimal current context and cached tool results; after delivery it must not replay the reply.
Repeated failure stays recoverable, with the user's message and found cards
available. An individual message still has the composer limit and can exceed a model's token budget
with unusual tokenization. No model-size policy can guarantee that arbitrary input always fits.

## Check it

```sh
make check BUILD_DIR=/tmp/sillies-check
SILLIES_CHAT_MODEL_CHECK=1 bash scripts/test.sh --filter 'appleChat|chatCompacts'
```

Default tests use injected backends and temporary Vaults. The opt-in checks exercise real Apple
inference with synthetic records and a bounded long conversation; they do not read the user's Vault
or download model weights. Test installed downloaded models separately before claiming their
end-to-end tool quality. See [text providers](text-models.md) for the runtime integration checklist.

The mixed-topic check deliberately tests saved links → general questions → a follow-up referring to
the earlier link. On the Apple model tested on 2026-11-01 this evaluation has both failed and passed;
fresh sessions with tools still performed irrelevant searches in the controlled comparison. Passing the
default injected-backend suite or one model run does not establish reliable native model quality. See the
[investigation and Apple references](../reports/chat-reliability-2026-11-01.md).
The [identity and memory evaluation](../reports/chat-identity-2026-11-01.md) also records unresolved
recovery from incorrect earlier replies. Keep those failures visible when comparing models.

For a controlled integration comparison, run:

```sh
SILLIES_APPLE_CHAT_COMPARISON=1 bash scripts/test.sh \
  --filter appleNativeAndApplicationTranscriptsUseIdenticalChatInputs
```

It compares identical app inputs across retained, restored and reconstructed native sessions and
both response APIs. It also counts
actual native session creation through the application service. Its assertions establish integration
behavior and follow-up continuity, not reliable tool-selection quality; retain the separate mixed-topic
evaluation above.

To run the same bounded evaluation against an already installed downloaded model, set
`SILLIES_DOWNLOADED_CHAT_MODEL_CHECK=1`, `SILLIES_CHAT_MODEL_STORE`, `SILLIES_CHAT_MODEL_ID`, and
`SILLIES_TEXT_HELPER`, then run `bash scripts/test.sh --filter downloadedChatAnswersGeneralKnowledge`.
This check does not download weights or read the user's Vault.
