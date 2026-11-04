# Local model readiness — 4 November 2026

This follow-up promotes **bounded prefix caching for Gemma 26B and LFM 24B**. Qwen 4B stays on its
existing path. A multilingual retrieval model deserves a production implementation, but the semantic
prototype and separate memory-creation/correction tools are not enabled in the app.

The starting point is `e61c21d` plus the frozen, uncommitted
[previous round](model-opportunities-2026-11-04.md). That round's Gemma E4B/Nemotron changes are
preserved; they are not counted as new improvements here. The
[registered study](../../Benchmarks/Chat/experiments/model-readiness-2026-11-04/study.json)
limits native execution to 3,600 seconds, with sequential, supervised batches and synthetic stores.
This run used **2,564.6 seconds** of that budget on one M4 Pro with 48 GiB RAM. No running app was
restarted, no live Vault was read, and no app model selection was changed.

| Track | Decision |
| --- | --- |
| Gemma 4 26B A4B prefix snapshots | Enabled after native state, lifecycle, memory and production-workflow checks. |
| LFM2.5 24B A2B prefix snapshots | Enabled after fixing an adapter contract mismatch and rerunning the workflows. |
| Qwen3.5 4B prefix snapshots | Withheld: faster, but both candidate runs omitted name writes; the baseline performed the later write. |
| Semantic memory search | E5 retrieval is promising; keep the research adapter out of production until index and lifecycle work is complete. |
| Separate create/correct tools | Rejected: below the registered improvement threshold, with an unauthorized rewrite in the Ministral run. |

These experiments do **not** update the full-corpus leaderboard or select a new default model.
Reviews were performed by the implementing agent, not an independent or blinded reviewer.

## Prefix snapshots

The helper renders the checkpoint's native messages and tools, compares tokens to locate a reusable
prefix, and retains one immutable native snapshot before the latest user content. Every use gets a
native copy. It never rewinds recurrent state or appends to the retained original. Both enabled
profiles cap retention at 2,048 tokens; logical state-array caps are 384 MiB for Gemma and 128 MiB
for LFM. The helper's allocation limit separately covers weights, active generation and temporary work.

Full-prompt admission still runs before generation. Sampling penalties see the full prompt, including
cached tokens. Session or model preparation changes invalidate reuse. Changed instructions, tools or
history within the prefix rebuild it; differences after it are processed normally. Cancellation and
failed streaming drain generation and clear ownership. Opaque native carried
state without a copy/size contract is forwarded to the current generation but never retained.

No new dependency or SDK fork is used. The pinned official runtime supplies native cache copying,
model preparation, generation and decoding constraints. Profiles select the implementation; algorithms
contain no model-name branches. Native arrays remain inside the helper's model-container isolation.

### Measured latency

Ten matched pairs per model alternate retained and rebuilt order, with greedy decoding and known
answers. Timing includes the normal measure request, generation, acknowledged IPC and delivery of the
first non-whitespace text. It excludes model loading, download verification and TTS. All 60 answers
were correct, and streamed text agreed with the final response.

| Model | Rebuilt median first text | Retained median first text | Reduction | Enabled? |
| --- | ---: | ---: | ---: | --- |
| Gemma 4 26B A4B | 2.667 s | 1.114 s | 58% | Yes |
| LFM2.5 24B A2B | 2.338 s | 1.008 s | 57% | Yes |
| Qwen3.5 4B | 3.124 s | 0.848 s | 73% | No |

Snapshot preparation has an initial cost. Three paired, already-loaded first-request controls measured
0.860 → 1.152 s for Gemma, 1.224 → 1.272 s for LFM, and 0.761 → 0.825 s for Qwen. These are different,
shorter prompts from the warm continuation test. They are not model cold-start times, and the warm
gain does not apply after every context change or reopened conversation.

### State, memory and lifecycle

- Three prompt sizes per checkpoint compared restored versus independently computed state with the
  **same split prefill**. Cache arrays, metadata and logits matched exactly; repeated restoration did
  not mutate the snapshot. The tested models returned no opaque carried state.
- Unsplit cold prefill produced different logits, although the top next token matched in all nine
  controls. The native runtime's balanced chunking depends on input length; splitting changes floating
  point evaluation. This is why native state tests alone cannot certify answer quality.
- Controls exercised changed history, instructions, tools and session identity; matching and unrelated
  releases; context rejection; generation failure; throwing output sinks; and cancellation during
  streamed output. Recovery rebuilt without stale tokens.
- Twelve growing-history requests per model retained a constant snapshot and stable active allocations.
  Three subsequent release/rebuild cycles returned to the same released allocation level. Twenty-three
  operations per model also exercised an actual checkpoint change and return, with zero reused tokens
  after each change. The logical snapshot limits and live allocation measurements are separate.
- Repeated in-process model replacement exposed approximately 408 MiB of additional native active
  allocations per round trip in **both** the unchanged baseline and candidate. This is not additional
  snapshot retention. Production already avoids this diagnostic pattern: `TextWorkerModel` has an
  immutable preparation, and `TextModelRegistry` stops/reaps the old worker before preparing a changed
  checkpoint or profile. That ownership and the existing registry replacement regression remain
  essential. The diagnostic does not establish that arbitrary native hot-swapping is memory-bounded.

Early diagnostic failures are retained. LFM's original lifecycle fixture returned a tool call without
visible text, so its text-sink injection never ran. Another fixture requested one answer token but
forgot LFM's separate 1,024-token reasoning allowance. Corrected fixtures exercise the intended
failure without changing product budgets. The capacity inspector initially applied a one-request
wire limit to a batch; its bounded batch reader was corrected before any model loaded.

### A real integration bug, investigated before promotion

The initial prefix implementation passed `[]` as the native tool schema after the application
exhausted its tool budget. The existing generation path passed `nil`. The SDK interprets `[]` as
an explicit empty allow-list and rejects any subsequent generated call; `nil` leaves parsing to the
normal application capability/quota handling. This caused LFM's candidate to fail a Vault task after
four searches, while the baseline delivered a quota response and completed its answer.

`MLXConversationInput.nativeTools` now owns this contract for ordinary, native-session and prefix
generation. A native parser regression checks the withdrawn-schema case. The application still
enforces tool capabilities and the same execution quota; parsing a late call does not authorize an
additional operation. The corrected LFM run completes the formerly failing lookup. No prompt,
expected answer, tool budget or output filter was changed to make it pass.

The six production scenarios contain seven turns: general knowledge, an explicit chat-only search,
saved URLs, mixed general/private knowledge, a question that must not overwrite a birthday, and name
creation followed by correction. Fresh temporary databases use the actual conversation service,
tool results and persisted memory state. The table uses complete rubric review, not lexical matches.

| Model | Baseline pass / fail / uncertain | Corrected candidate pass / fail / uncertain |
| --- | --- | --- |
| Gemma 26B | 5 / 1 / 0 | 5 / 1 / 0 |
| LFM 24B | 4 / 1 / 1 | 5 / 0 / 1 |
| Qwen 4B | 4 / 2 / 0 | 5 / 1 / 0 |

Gemma still misses the mixed question's Vault owner. LFM's uncertain candidate correctly reports no
chat evidence but claims five searches ran when the fifth encountered the quota; this is not counted
as a complete pass. Its baseline had an overbroad absence claim in a different task.

Qwen's aggregate case score hides a problem: its baseline missed the initial name save but persisted
the later name. Both candidate runs persisted neither. The delivered user messages and write tool
were present, no rejected call was reported, and the replies simply acknowledged the names without
calling the writer. The first run's schema bug does not explain this case, which still had tools.
Sampling and changed prefill numerics are not isolated causes here. Qwen therefore remains disabled
until a larger paired memory-write comparison resolves the difference. The timing gain alone is not
used as permission to weaken memory behavior.

## Semantic memory retrieval

The native prototype uses the existing pinned official `MLXEmbedders` implementation with
[`intfloat/multilingual-e5-small`](https://huggingface.co/intfloat/multilingual-e5-small), pinned to
`614241f622f53c4eeff9890bdc4f31cfecc418b3`. Only this experiment downloaded its approximately
449 MiB weights into an isolated temporary directory. It follows the model's query/passage prefixes,
masked mean pooling and L2 normalization, without an extra layer-normalization step. It uses Swift
inference, not Python inference. The experimental dependency and helper entry point were removed
from product sources; prototype source snapshots and artifact hashes remain in the evidence.

The frozen set contains 36 facts and 76 queries. Previous-round queries are development data, not
new held-out evidence. New validation includes 18 facts with both a question and keyword form, plus
eight absence questions with both forms. Ownership filters run before ranking. Expected identities
stay outside the inference worker.

| Retrieval method | New positive queries: top 1 / 36 | Top 4 / 36 |
| --- | ---: | ---: |
| Existing keywords | 28 | 31 |
| Apple sentence embeddings | 10 | 13 |
| Apple contextual mean embeddings | 14 | 17 |
| Native multilingual E5 | 29 | 36 |

These are 36 query variants over **18 facts**, not 36 independent facts. E5's median warm query
embedding took about 2.3 ms, excluding loading and index construction. It preserved the tested exact
identifier and ownership controls. Related but non-answering candidates still appear for absence
questions, with high cosine scores; no universal cutoff was fitted to these test answers.

### Retrieval must be tested through an actual answer

The first end-to-end fixture was invalid for this comparison: seeded memories' provenance messages
were also inside recent chat context. Correct replies could bypass retrieval. Those runs are retained
and excluded. A new frozen fixture moves source messages out of recent context and verifies their
absence from the **initial instructions and messages**, while allowing later retrieved evidence.
The evaluator now has an `initial_context_omits` check and prevents manual rubric passes on a failed
fixture. Tests distinguish this from compaction checks, where a summary may legitimately hold facts.

The corrected comparison has eight answerable and eight unanswerable personal questions per model.
Each real model-generated query is embedded natively; there is no expected-query lookup table. Both
arms have identical source records and production prompts. Full-rubric review checks the returned
evidence, answer, requested lookup and actual persisted state.

| Answer model | Keywords: pass / fail / uncertain | E5: pass / fail / uncertain |
| --- | --- | --- |
| Gemma 26B | 13 / 2 / 1 | 15 / 1 / 0 |
| Qwen 4B | 13 / 2 / 1 | 15 / 0 / 1 |

Both E5 arms recovered the previously missed quiet-room preference. Qwen also recovered swimming
days. No E5 answer invented the requested missing personal attribute in these eight negative cases.
Gemma skipped the explicitly requested salary lookup in both arms. Qwen's E5 coffee answer quoted
the correct restriction but contradicted itself about knowing the stopping time; it is uncertain,
not a pass. These small single-pass results do not certify reliable absence detection.

The benchmark bridge starts an embedding helper for each query and hashes its inputs, so its total
answer latency is not an optimized product latency. It cannot maintain vectors for new or corrected
facts. Shipping it as-is would produce slow starts and stale or missing embeddings.

The next implementation should include:

1. An optional downloadable embedding provider using the existing model store and inference admission.
2. A derived index keyed by companion, memory ID, source revision and embedding-model revision.
3. Atomic visibility for corrections/deletions, bounded background indexing, restart/cancellation tests,
   and lexical fallback while the model or index is unavailable.
4. Hybrid lexical/semantic candidates, with exact identifiers preserved and related evidence clearly
   distinguished from an answer. No score threshold trained on this frozen validation set.
5. Fast index-scale and contention tests, followed by independent paraphrases and human review.

## Separate memory creation and correction

The candidate made `save_memory` create-only and introduced `replace_memory` with required ID and
revision. It retained the existing transactional writer and added one general instruction to handle
an explicit durable assertion alongside a question. No per-case examples or inferred writes were used.

| Model | Prior baseline tasks / 9 | Candidate tasks / 9 |
| --- | ---: | ---: |
| Granite 4.2 3B | 6 | 5 |
| Ministral 3 8B | 6 | 5 |
| Gemma 4 12B | 6 | 7 |

No candidate reached the registered two-task gain. Ministral rewrote a birthday during a read-only
question, keeping its value but changing revision/provenance to the question. Gemma attempted a
creation from a question; the store refused the duplicate. All three missed a new preference embedded
in a general question. The separate tools and candidate prompt were removed. Confirmation and reserved
runs were not spent on candidates that failed the screen.

## Evidence and verification

The [evidence directory](data/model-readiness-2026-11-04/README.md) contains frozen corpora, native
probe receipts, failed experiments, source snapshots, binary/model hashes, manual reviews and exported
audits. Automatic checks and reviewed totals are recomputed from recorded evidence. Audits establish
integrity, not semantic perfection or statistical confidence.

`make check BUILD_DIR=/tmp/sillies-model-readiness-check` passed, including Swift format, architecture
checks, the headless test suites, fixture validation, helper self-checks and parent-exit checks.
Validation includes the benchmark evaluator regressions, native cache ownership and full-prompt
sampling checks, tool-schema regression, profile/cap validation, and the repository's headless
`make check`. No multi-hour soak, live recording or visible GUI test was used.
