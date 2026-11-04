# Model opportunities and benchmark review — 4 November 2026

This study starts at `e61c21d`. It investigates all five proposed opportunities independently:
memory-contract coverage, stable-prefix snapshots, remaining native-cache coverage, semantic memory
retrieval, and separate create/correct tools. The [registration](../../Benchmarks/Chat/experiments/model-opportunities-2026-11-04/study.json)
sets a 3,600-second aggregate native-execution limit, sequential batches with hard deadlines, frozen
inputs and explicit acceptance gates. All work uses synthetic temporary stores on one M4 Pro with
48 GiB RAM. No models are downloaded and the running app is not restarted.

| Investigation | Decision |
| --- | --- |
| Memory contract across all thirteen models | Completed diagnostic coverage; missed writes and false acknowledgements remain. |
| Stable-prefix snapshots for Gemma 26B, LFM 24B and Qwen 4B | Large prototype speed gains; not enabled because full native-state and lifecycle acceptance remains unproven. |
| Native cache on six remaining checkpoints | Enable the existing native-session implementation for Gemma E4B and Nemotron after matched tests and invalidation controls. |
| Local semantic memory retrieval | Contextual embeddings improve this small retrieval set, but are not ready for production retrieval. |
| Separate create/correct tools | Corrected experiment improves each tested model by one task; below the registered two-task threshold, so not promoted. |

These subsets do not update the full-corpus leaderboard or the default model. No speculative warming,
new inference dependency, checkpoint-template change or answer-specific filter is introduced.

## 1. Memory contract across thirteen models

The baseline worker was rebuilt from the starting commit. Nine frozen scenarios contain ten turns
per model: a new preference combined with world knowledge, a birthday question that must not become
a correction, name creation/correction, a fictional quotation, a chat-only request with tempting
Vault evidence, world knowledge, saved URLs, a correction among 97 saved facts, and an explicit
memory opt-out combined with a general question.

All 117 cases have receipts, including failures. Reviews bind to the entire observed turn, calls,
tool results, saved state and rubric. Automatic lexical checks remain separate.

| Model | Complete task passes / 9 | Failed | Uncertain |
| --- | ---: | ---: | ---: |
| Gemma 4 26B A4B | 8 | 1 | 0 |
| Granite 4.2 8B | 7 | 2 | 0 |
| Nemotron 3.5 Bolt E4B | 7 | 2 | 0 |
| Qwen3.5 4B | 7 | 2 | 0 |
| Gemma 4 12B | 6 | 3 | 0 |
| Gemma 4 E4B | 6 | 3 | 0 |
| Granite 4.2 3B | 6 | 3 | 0 |
| Ministral 3 8B | 6 | 3 | 0 |
| LFM2.5 24B A2B | 5 | 4 | 0 |
| Qwen3.5 9B | 4 | 4 | 1 |
| LFM2.5 2.6B | 3 | 5 | 1 |
| Apple Intelligence | 2 | 7 | 0 |
| Qwen3.5 2B | 2 | 6 | 1 |

This is one stochastic diagnostic pass, not a new model ranking or a reliability estimate. The
implementing agent reviewed it; there is no independent or blinded human review. Three replies have
unresolved additional claims or inconsistent explanations and are not counted as passes.

The new preference is missed across all models in this pass. Several models acknowledge names
without saving them. The writer refuses malformed references and reference-free overwrites of an
existing canonical topic, but cannot prevent a model from falsely claiming success in its prose or
inventing a second topic key for the same real-world fact. Correct storage semantics do not establish
correct memory decisions.

Failures were inspected through delivered instructions, tool definitions, roles, arguments, search
results and stop reasons. Gemma 12B's baseline correction reaches its 60-second deadline after a
malformed revision is refused. LFM 2.6B exhausts its output allowance in two turns, including one
with 5,947 private-reasoning bytes and no visible answer. Other misses often make no write call at
all. These are observed app-task failures; this study does not prove they are intrinsic model limits.

The older worker snapshots record fact values and source quotes. Identity/revision evidence comes
from executed search and write receipts, rather than a separate identity field in the snapshot.
Future workers now record persisted IDs, revisions and source-message IDs explicitly. A missing
snapshot after a timeout is never treated as an empty store.

## 2. Stable-prefix snapshots

The experimental helper renders the checkpoint's own structured messages and tools, finds an exact
token prefix before the final user question, prepares it once, and clones native cache state for
each matching request. A mismatch rebuilds from the complete input. It uses the pinned official
runtime's public APIs and checkpoint generation restrictions; no upstream fork is adopted.

The first prototype omitted the batch axis when forwarding the remainder returned by
`model.prepare`. All three helpers failed before a measured answer. Crash stacks identify the
diagnostic's snapshot preparation, not the production helper. The correction follows the native
iterator/reranker convention. Failed logs, the earlier source and the corrected source are preserved.

Five short questions and three changed-input controls then complete for each model. The controls
change earlier history, instructions or tools; all rebuild and answer from the changed input.

| Prototype median first visible text, five questions | Rebuilt | Restored | Initial prefix preparation | Logical snapshot state |
| --- | ---: | ---: | ---: | ---: |
| Gemma 4 26B A4B | 2.390 s | 0.124 s | 2.420 s | 234.6 MiB |
| LFM2.5 24B A2B | 2.246 s | 0.468 s | 1.866 s | 36.6 MiB |
| Qwen3.5 4B | 2.880 s | 0.074 s | 2.660 s | 114.1 MiB |

The expected fact is correct in every answer. One LFM pair differs in punctuation. These are
in-helper measurements: model loading, IPC and initial prefix preparation are outside the timed
follow-up. They cannot be compared directly with app first-text timings. Logical array sizes are
not additional process RSS; backing allocations and cloned live caches also matter.

**Not promoted.** This probe has no production snapshot owner spanning cancellation, failed tool
turns, session release, model changes and growing context. Matching answers do not establish native
state equivalence. It also lacks a repeated large-context memory bound and independent confirmation.
The registered lifecycle/state gates remain unmet, so the prototype is archived rather than added
to normal inference. A future implementation must satisfy those gates before enabling any profile.

The official SDK has an [open prefix-checkpoint proposal](https://github.com/ml-explore/mlx-swift-lm/pull/716)
for caches that cannot rewind after template changes. It documents additional requirements around
cache leaves, carried state and unsupported inputs. It was unmerged when checked; this study does
not change the pinned dependency or treat the proposal as a released capability.

## 3. Native-cache coverage and production change

Six checkpoints receive three matched retained/rebuilt pairs each. Gemma E4B and Nemotron qualify
for ten further pairs each: five questions repeated twice with alternating execution order. All
forty confirmation answers match the expected values. Temperature is zero for these native probes;
product sampling is unchanged. Each request includes acknowledged streaming and token measurement.

| Warm follow-up first text, ten-pair median | Rebuilt | Retained | Reduction |
| --- | ---: | ---: | ---: |
| Gemma 4 E4B | 1.628 s | 0.608 s | 62.6% |
| Nemotron 3.5 Bolt E4B | 1.662 s | 0.612 s | 63.2% |

Gemma reuses 1,767 prompt tokens and Nemotron 1,766. All nine controls pass for each: unchanged
history, edited history, changed instructions, changed tools, changed session identity, current
session end, unrelated session end, context rejection and generation failure. Only unchanged history
and ending an unrelated session preserve reuse. These are bounded warm-follow-up diagnostics on
one Mac, not full-task latency guarantees.

Gemma 12B, LFM 2.6B and Qwen 2B/9B report zero cached tokens in the screen and do not qualify.
LFM also requests an unnecessary Vault search in one probe. Runtime cache reconciliation and the
app's refusal to retain private reasoning are distinct constraints; zero reuse does not alone
identify which constraint dominated every turn. Their profiles remain unchanged.

The two enabled profiles select the existing `nativeSession` abstraction. Ownership, admission,
cancellation, session release and fallback remain in the existing runtime. No model-name branch or
manual recurrent-cache trimming is added. Cold requests still process their prompt normally.

Both profiles also complete all nine contract scenarios through the production conversation service,
with real tools and synthetic storage: 20 turns, no transport or generation errors. Reviewed task
counts remain 6/9 for Gemma E4B and 7/9 for Nemotron, the same as their baseline pass. Name follow-ups
reuse 1,315 and 1,306 tokens respectively; Nemotron also reuses 2,909 tokens while completing the
reference-checked courier correction. Some tool transitions correctly rebuild. No quality improvement
is claimed from this single stochastic pass.

## 4. Semantic memory retrieval

Two native Apple candidates use already-installed Natural Language assets: sentence embeddings and
mean-pooled contextual token embeddings. No system assets are downloaded. Sentence vectors from
different language spaces are not compared. Contextual vectors are compared only within the same
model identifier/revision. Language availability does not establish cross-language alignment.

The frozen inputs contain 17 facts and 24 queries, including owner separation, exact identifiers,
paraphrases, cross-language requests and no-match queries. Gold identities remain outside the worker.
The lexical baseline calls the actual conversation store. Semantic retrieval filters by owner before
ranking. These are direct full-sentence queries; normal Chat instructs its model to produce short
search keywords. This is a retrieval diagnostic, not an end-to-end Chat comparison.

| Retrieval of expected fact in first four candidates | Development | Reserved validation | Median query |
| --- | ---: | ---: | ---: |
| SQLite lexical search | 8/10 | 5/11 | 0.094 ms |
| Apple sentence embedding | 6/10 | 5/11 | 2.969 ms |
| Apple contextual embedding, mean pooling | 9/10 | 9/11 | 7.603 ms |

The three no-match queries are excluded from the positive-query recall denominators and reported
separately: **all three methods return four irrelevant candidates for each**. Contextual top scores
range from 0.827 to 0.874 and overlap relevant results. A global similarity cutoff would be an
unvalidated guess. Cross-language pet-name and unit-preference queries also miss their facts.
Exact identifier and owner controls pass. Indexing the small semantic fixture takes 0.261 seconds
for sentence embeddings and 0.892 seconds for contextual embeddings, including asset loading.

**Not promoted.** The contextual result is promising for a hybrid keyword/semantic retriever, but
the pooler, no-match behavior and cross-language quality need broader validation. This prototype
scans 17 fact vectors; it proves nothing about a persistent index with thousands of facts. No
production embedding model is selected, no automatic retrieval threshold is introduced, and memory
search continues using the existing lexical index. A subsequent study should compare a purpose-built
multilingual retrieval embedding and a bounded index with exact lookup preserved.

## 5. Separate create/correct tool experiment

The first implementation changed schemas and app instructions but the benchmark's fixed `app`
allowlist silently omitted the new `replace_memory` tool. Gemma's rejected call was an integration
defect in the benchmark. Those 27 cases remain in the evidence as **invalid experimental runs**;
they support no conclusion about the split design or a model's capability.

After repairing the profile and verifying all six delivered definitions, the same candidate is
tested again in separate result directories. Persistence transactions, model settings and frozen
rubrics are unchanged. The automatic correction check still names `save_memory`; its failure is
preserved, and full-rubric review checks the actual `replace_memory` operation and committed state.

| Complete tasks / 9 | Baseline | Correctly wired split |
| --- | ---: | ---: |
| Granite 4.2 3B | 6 | 7 |
| Ministral 3 8B | 6 | 7 |
| Gemma 4 12B | 6 | 7 |

All three correct the existing courier fact with a real reference-checked write. New preferences
remain missed, as do names for Granite and Ministral. Each gains only one complete task, below the
registered two-task gate. Confirmation repetitions and the six reserved validation scenarios are
therefore **not run**. The schema/prompt experiment is reverted; it is not enabled for any model.

## Benchmark integrity changes

The app profile now admits the actual production capabilities. Explicit ablations retain their
restricted sets; expanded profiles add only enough distractors to reach their requested total.
Fixture self-checks cover future-tool inclusion and preserved restricted profiles.

The evaluator review also adds these protections:

- Export recomputes its summary from receipts and current reviews instead of trusting a stale file.
- Audit verifies published review totals as well as automatic primary metrics. Legacy partial review
  summaries are marked separately; they do not certify a full-rubric score.
- Missing memory snapshots cannot pass a memory-absence check. Whitespace is not a completed answer.
- Failed/empty turns and failed cases cannot receive full-task passes through manual review.
- Persisted memory snapshots include IDs, revisions and source-message identities. Self-checks verify
  that correction preserves identity while changing revision and provenance.

Adversarial evaluator tests cover these failure inputs. Existing checks retain failed/missing cases,
reject stale reviews and changed execution identities, and keep gold answers outside model inputs.
During this audit, resume correctly rejected an evaluator/catalog change between batches. The
remaining cases resumed only after restoring the exact recorded evaluator digest in a frozen
directory; completed cases were not rerun or rewritten. The
[amendment log](../../Benchmarks/Chat/experiments/model-opportunities-2026-11-04/evaluation-notes.json)
records both benchmark defects and their repairs.

Recomputation establishes consistency, not independent proof of scoring logic or factual truth.
The tests, complete evidence review and explicit uncertainties are complementary. No claim of a
bug-free benchmark, cross-hardware reliability or production-ready automatic memory is made.

## Evidence and reproduction

The [data directory](data/model-opportunities-2026-11-04) contains the execution ledger, logs,
native probes, source snapshots for discarded experiments, frozen binary hashes, per-model app
archives, manual reviews and fresh audit receipts. Failed and invalid experiments are preserved.
The [benchmark guide](../../Benchmarks/Chat/README.md) describes bounded execution, export and audit.
Use the registered contract corpus for reproduction; native probes require the matching installed
checkpoint revisions. Experimental source snapshots are research artifacts, not enabled app paths.

Native execution used **2,110.6 of the registered 3,600 seconds**, including invalid experiments and
their recorded repairs. Batches are sequential and individually bounded; no soak test runs for hours.

Final validation: `make check` passes, including headless native presentation tests, all 74 synthetic
benchmark fixtures, inference-helper self-checks, parent-exit lifecycle checks, localization and
catalog validation. The 37 evaluator/audit tests pass. All 21 exported app archives reproduce their
checks and published review summaries; three archives are explicitly invalid experiments. A separate
state cross-check verifies all nine passing courier-correction reviews against the frozen unrelated
facts, current provenance and exact search/write references. These checks support the reported
diagnostic results without certifying broad model accuracy.
