# App-only experiments by model — 3 November 2026

The retry found a strong native-cache opportunity for Granite 8B, a promising but incompletely
validated memory-context result for Qwen 4B, and an input-contract failure in Ministral. No
experimental inference behavior is enabled in the app. The [frozen plan](app-strategies-plan-2026-11-03.md)
and [evidence bundle](data/app-strategies-2026-11-03/README.md) preserve the controls, prototypes,
reviews and stopping decisions. Nothing was committed, pushed or loaded into the running app.

The study records **491 scenario results / 538 turns**, plus **40 matched native cache pairs**.
It used 3,564.9 seconds of the 3,600-second supervised native-execution budget, including the last
interrupted batch. This is execution time, not total wall time spent developing and reviewing the
study. All models ran serially on one Apple M4 Pro Mac with 48 GiB RAM and macOS 26.7.2.

## Native session-cache result

A concrete opportunity exists for **Granite 4.2 8B** in the pinned MLX runtime. It reused 2,026
prompt tokens and produced the same correct short answers across ten matched follow-ups. This is
an adapter integration opportunity, not an already-shipped Sillies improvement.

Each model received the original app instructions and five tool definitions, synthetic planning
notes, and five distinct follow-up questions repeated twice. The two arms alternate execution
order. The retained arm uses public `ChatSession`; the control reconstructs visible history.
Both preserve the model's generation profile and checkpoint restrictions, with a common 96-token
visible-output limit plus its existing reasoning allowance. No tool executes in this probe.
The first visible non-whitespace answer is timed after provider channel separation. Model loading
and the initial notes turn are outside these follow-up measurements. Native models run serially.

| Model | Rebuilt first text p50 / p95 | Retained first text p50 / p95 | Reused tokens | Exact answers, rebuilt / retained |
| --- | ---: | ---: | ---: | ---: |
| Granite 4.2 8B | 5.454 / 5.519 s | 0.150 / 0.213 s | 2,026 of 2,048–2,049 | 10/10 · 10/10 |
| Gemma 4 26B A4B | 2.649 / 2.767 s | 2.660 / 2.814 s | 0 | 10/10 · 10/10 |
| LFM 2.5 24B A2B | 2.296 / 2.371 s | 2.309 / 2.417 s | 0 | 10/10 · 10/10 |
| Qwen 3.5 4B | 2.771 / 2.840 s | 2.769 / 2.837 s | 0 | 10/10 · 9/10 |

These medians include every observed follow-up, not a cherry-picked subset. Qwen's exact-format
miss was `Cobalt.` instead of the requested value alone; the fact was correct. Its zero reuse and
near-identical timing do not support an optimization claim. Granite's ten pairs all satisfy the
exact-answer and normal-completion checks. Its total follow-up median also improved, from 5.492
to 0.204 seconds. These numbers must not replace the app benchmark's first-text leaderboard.

### Why the models differ

The difference is visible in the native templates and cache policy, not just wall-clock noise.

- Granite's subsequent prompt extends the initial prompt; the retained native session serves the
  matching prefix from cache and processes only 22–23 new prompt tokens.
- Gemma inserts an empty thought-channel prefix for the current response. When that response
  becomes history, the template omits the prefix. Our tokenizer replay confirms the mismatch.
  Its checkpoint has a 1,024-token sliding window, already wrapped by the roughly 1,768-token
  opening. MLX deliberately refuses an exact rewind of wrapped rolling caches, then rebuilds.
- LFM's current-turn `<think>` prefix and Qwen's empty thinking block also disappear in rendered
  historical answers. Their recurrent state cannot use ordinary KV trimming. This repeats the
  earlier Qwen 2B finding on additional installed models; it does not establish that all possible
  caching strategies are impossible for these architectures.

The relevant pinned implementation is
[MLX ChatSession](https://github.com/ml-explore/mlx-swift-lm/blob/3b339ad6e3b3f44c8121ecff5131c7fd55e075e6/Libraries/MLXLMCommon/ChatSession.swift),
its [reuse policy](https://github.com/ml-explore/mlx-swift-lm/blob/3b339ad6e3b3f44c8121ecff5131c7fd55e075e6/Libraries/MLXLMCommon/PromptCacheReusePolicy.swift),
and [cache rewind contract](https://github.com/ml-explore/mlx-swift-lm/blob/3b339ad6e3b3f44c8121ecff5131c7fd55e075e6/Libraries/MLXLMCommon/KVCache.swift).
No dependency, template, token stream or native cache implementation was patched for the probe.

An app implementation still needs exact continuation matching, model/session ownership, bounded
retention, invalidation when context or tools change, cancellation, pressure eviction and faithful
reasoning/tool state within a turn. The existing `TextConversationContinuation` and Apple's native
session owner provide useful tested boundaries; MLX's private channels require their own integration
checks. A session-cache switch for every provider would not produce the Granite result elsewhere.

## Quality experiments

The two candidates change different responsibilities and are not combined. Split writes exposes
six tools and removes replacement references from new writes. Memory context keeps five tools and
supplies at most four already-saved facts before the reply. Neither adds another inference call.

The source and persistence traces distinguish several failure classes:

- Apple invents a replacement identity on a new name; the existing writer rejects it. Splitting the
  schemas removes that malformed create call but leads to greetings stored under separate name keys,
  leaving both old and new names. This is not a successful correction.
- Gemma 12B's split variant answers the birthday question correctly, then unnecessarily saves the
  unchanged date. Because creation retains the existing stable-key upsert, the question replaces
  the original statement as provenance. The candidate is rejected after four admitted cases.
  This tests a tool-schema split, not an insert-only persistence design; both the generated write
  decision and the existing write contract contribute to the outcome.
- Many models answer the general question while omitting the accompanying preference write. The
  native traces contain no corresponding call, so this is not a lost persistence completion.
  A fluent acknowledgment is also not evidence of a committed name change.
- LFM 24B's quotation failure continues emitting tool calls after four executed calls and after
  the runtime has removed available tools. Both the bounded final-answer attempt and its retry
  still return a call, producing `invalidResponse`. Empty search results were delivered; there
  is no evidence here that a result was lost or that valid tool syntax was discarded.
- LFM 2.6B reaches `contextLimit` during one correction turn: repeated searches accumulate active
  reasoning and evidence within its working context. No history compaction runs in that turn.
  This is an interaction between turn behavior and the shipped context budget, not growth of the
  complete archive. Increasing a budget would need its own latency/correctness comparison.

The manual rubric review also catches weaknesses in lexical scoring. An answer naming the
fictional speaker Ivo can be correct without the word “narrator.” A birthday response that contains
the expected date but says it does not know and asks for confirmation is not a successful recall.
Conversely, an extra wording concern outside a frozen task's rubric is recorded without silently
adding a new scoring requirement. Reviews are bound to full evidence hashes and are not blinded
or independently human-reviewed.

### Original eight-scenario screen

A case passes only if every turn passes its frozen rubric. Counts below are manually reviewed
application tasks, not model capability scores. All thirteen models completed both the control
and memory-context screen; the split-write candidate stopped early for Gemma 12B.

| Model | Control | Split writes | Preloaded memories |
| --- | ---: | ---: | ---: |
| Gemma 4 E4B | 5/8 | 6/8 | 6/8 |
| Gemma 4 12B | 6/8 | 3/4 · stopped | 6/8 |
| Gemma 4 26B A4B | 7/8 | 7/8 | 7/8 |
| Granite 4.2 3B | 5/8 | 5/8 | 6/8 |
| Granite 4.2 8B | 6/8 | 6/8 | 6/8 |
| LFM 2.5 2.6B | 4/8 | 4/8 | 4/8 |
| LFM 2.5 24B A2B | 5/8 | 6/8 | 5/8 |
| Ministral 3 8B | 5/8 | 4/8 | 5/8 |
| Nemotron 3.5 Bolt E4B | 6/8 | 6/8 | 6/8 |
| Qwen 3.5 2B | 3/8 | 4/8 | 2/8 |
| Qwen 3.5 4B | 6/8 | 6/8 | 6/8 |
| Qwen 3.5 9B | 6/8 | 6/8 | 5/8 |
| Apple Intelligence | 2/8 | 2/8 | 2/8 |

Qwen 2B's preloaded-memory arm also has one uncertain quotation answer; it is not counted as a
pass. Ministral has one template-integration failure in each arm. Nemotron's split-write arm claims
a name update without committing it and is rejected despite an unchanged aggregate. No split-write
candidate gains the required two tasks. Several apparent gains or losses occur on inputs with no
saved facts; sampling and schema changes confound single-pass causal claims.

The separate older-history controls and any confirmation runs are reported below; they do not
replace or selectively repair this initial screen.

### Facts outside recent chat

These four controls place the original fact behind 80 intervening messages. They test owner
identity, a question about an existing birthday, mixed personal/general knowledge, and an explicit
meetings-only source restriction. This prevents recent visible dialogue from masquerading as
successful long-term memory retrieval.

| Model | Control | Preloaded memories |
| --- | ---: | ---: |
| Gemma 4 E4B | 1/4 | 3/4 |
| Gemma 4 12B | 2/4 | 2/4 |
| Gemma 4 26B A4B | 3/4 | Not admitted |
| Granite 4.2 3B | 1/4 | 2/4 |
| Granite 4.2 8B | 3/4 | 3/4 |
| LFM 2.5 2.6B | 3/4 | 1/4 |
| LFM 2.5 24B A2B | 4/4 | 3/4 |
| Ministral 3 8B | 2/4 | 3/4 |
| Nemotron 3.5 Bolt E4B | 1/4 | 3/4 |
| Qwen 3.5 2B | Not admitted | Not admitted |
| Qwen 3.5 4B | 1/4 | 4/4 |
| Qwen 3.5 9B | Not admitted | Not admitted |
| Apple Intelligence | 1/4 | 2/4 |

Gemma 12B, both Granites, LFM 24B, Ministral and Nemotron lose a previously passing source-scope
control when facts are preloaded. LFM 2.6B also confuses identities. Apple improves name attribution
in this sample, but still adopts the human's home city as its own and ignores meetings-only scope.
Ministral's control unnecessarily rewrites an existing name during recall and replaces its original
source with the question; the candidate avoids that write but loses the meetings-only task.
The control itself is not a correctness guarantee.

Qwen 2B and 9B were not admitted to these extra controls after losing the saved-URL task in the
original screen: they could no longer satisfy the registered no-regression condition. Gemma 26B's
control already passed three of four extra tasks and its original screen had no gain; the maximum
remaining gain was one, below the registered two-task requirement. Its candidate extra arm was not
admitted. These omissions remain visible in the frozen run metadata.

### Gemma E4B confirmation and reserved validation

Gemma E4B met the registered task-count screen, so it received two further matched repetitions
of all twelve scenarios and then the six frozen validation scenarios. No prompts, weights or
profiles changed between these runs.

| Comparison | Control | Preloaded memories |
| --- | ---: | ---: |
| Initial twelve-scenario screen | 6/12 | 9/12 |
| Confirmation repetition 1 | 7/12 | 9/12 |
| Confirmation repetition 2 | 6/12 | 9/12 |
| Reserved validation | 2/6 | 4/6 |

This is a repeatable recall signal: the candidate supplies the human name and birthday that the
control declines to retrieve. In validation it also correctly replaces a hobby using the supplied
real memory identity and revision; the control merely claims an update while leaving storage
unchanged. The other additional validation pass is screenshot delivery, but that input has no
saved facts, so a single sampled improvement there cannot be attributed to preloading.

**Passing the task-count gate is not enough to recommend this variant for production.** In all
three mixed city/mountain probes, it recalls Braga but answers Aconcagua instead of Everest.
The control answers Everest while failing the city portion; both fail the complete task, hiding
this component regression in the aggregate. The candidate also retains the mixed Vault/general
question failure and the missed preference write. Its Spanish validation answer gives an incorrect
trapped-air explanation for floating ice. These are reported rather than repaired with filters.
No model-training limitation is inferred from this small integration study.

The result supports further work on selective memory context, but not a global preload switch.
The prototype remains archived and disabled. A future acceptance rubric should score each part
of mixed questions independently as well as the whole task; this study's frozen scores are not
rewritten after the fact.

### Qwen 4B: promising, incomplete confirmation

| Comparison | Control | Preloaded memories |
| --- | ---: | ---: |
| Initial twelve-scenario screen | 7/12 | 10/12 |
| Confirmation repetition 1 | 8/12 | 10/12 |
| Confirmation repetition 2 | 3 passes from 3 completed; 9 pending | 10/12 |
| Reserved validation | Not started | Not started |

The preloaded variant recalls the old name, birthday and home city, keeps Pogo's identity separate,
and respects the meetings-only restriction in its initial run and both repeats. It still fails to
save a new name or the preference accompanying a general question. The first complete matched
repeat retains a two-task gain with no lost passing task. The remaining control comparison is
incomplete, so the second candidate result is **not** treated as a confirmed improvement.

The final paired batch reached its registered 170-second interruption deadline, leaving ten
seconds for teardown within the 180-second cap. It stopped during the second control repetition;
validation never started. Total study execution remained below 3,600 seconds, but the remaining
35.1 seconds cannot admit another supervised batch. No timeout is converted into a model-quality
score, and pending jobs are not removed from planned coverage. Qwen remains a candidate for further
validation, not an enabled product policy.

## Ministral role-format failure

Ministral's short seeded-birthday case fails before generation in all three arms. The fixture
persists the original human statement, then the current question; both are user-role messages.
Its installed template rejects that sequence. Tokenizer-only controls reproduce the exception
with consecutive user entries and succeed with alternating roles or a joined user entry.
No model weights or generation are involved in that reproduction.

This is an input-contract integration failure, not evidence that Ministral cannot recall a
birthday. It remains a failed application task in the diagnostic counts, with that cause
identified explicitly. The benchmark fixture exposes it; app history can also lack an assistant
reply when an attempt fails before producing text. A robust native input policy needs tests for
that case, interrupted empty replies, tool turns and preserved source attribution. The joined
control establishes renderability only; it is not a production normalization implementation or
proof that merging messages preserves every conversational meaning.

The archived native-probe evidence contains the exact input requests and template error. No
fixtures were rewritten after inference to hide this failure.

## What this does not retest

Exact tokenization caching, Apple native continuation, per-model working contexts and prefill
choices, checkpoint token restrictions, bounded background checkpoints and improved archive
passages already ship. The [provider report](provider-optimization-2026-11-01.md) measured exact
823-token prompt preparation at 9.84 ms before and 0.124 ms after the existing tokenization cache.
A duplicate cache would add ownership complexity without demonstrating a new benefit.

The previous [memory study](memory-improvement-2026-11-03.md) rejected a separate extraction phase,
including a refined ownership/source wrapper. Scheduling the same unreliable extractor in the
background does not repair its semantic decisions. This retry keeps that negative evidence and
investigates a different tool contract and evidence preparation instead.

## Engineering decisions and next work

1. **Integrate and measure bounded native continuation for Granite 8B.** The runtime probe supports
   this investment. Preserve exact state and prompt matching, tool/reasoning history, cancellation,
   context changes and bounded eviction before claiming an app speedup.
2. **Fix the native input contract for Ministral.** Reproduce interrupted/retried conversations in
   application tests and preserve message attribution without inventing assistant statements.
3. **Finish the frozen Qwen 4B comparison before enabling memory preparation.** A generic memory
   preparation component can be configured per model; this trial only tested four recent facts,
   not semantic ranking across a large store. Add distractors and independently scored mixed-question
   parts to a future corpus. Do not relabel those new tests as held-out evidence for this study.
4. **Keep write semantics separate from tool wording.** If split writes are retried, creation must
   have a deliberate persistence contract; retaining stable-key upsert does not make it insert-only.
   Structural reference, revision and provenance guarantees cannot replace semantic decision checks,
   and a false tool choice must not be hidden by a case-specific output filter.

All production prototype changes were restored to the pre-study state. Retained changes are the
experiment registrations, evidence, reports and a benchmark regression that recognizes both create
and replacement attempts in `no_writes`. The previously existing memory-commit timing instrumentation
was preserved. The published model leaderboard remains unchanged.

## Validation and limits

`make check` passed after restoring production behavior: 93 Python tests, 707 selected Swift tests
across 18 runs, formatting and architecture checks, 74 benchmark fixtures, localization, native
helper self-tests and helper termination checks. The separate build directory left the running
local app untouched. The [evidence bundle](data/app-strategies-2026-11-03/README.md) includes the
completion receipt and full log. All eleven benchmark archives reproduce their recorded results
through the audit command. Source overlays and readable patches preserve the exact prototypes
without enabling them in production.

This is a small synthetic study on one Mac and primarily English prompts, with limited Spanish
validation. There is no uniform provider RNG control. Review was performed by the same agent that
conducted the study, without blinding or independent human review. Native cache results exclude
loading, UI rendering and TTS. Many older-history cases contain only one saved fact; they cannot
establish retrieval quality across a crowded memory store. These results evaluate the complete
model/runtime/app configuration and do not establish a model's maximum capability.
