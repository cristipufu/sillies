# Can we trust the Chat benchmark?

**Audit · November 2, 2026**

We can trust the recorded examples as evidence of what this app configuration did. The original
497 case receipts and all primary metrics reproduce from their saved inputs, outputs, actions and
checks. We should **not** treat the automated totals as complete answer-quality scores, proof of
long-term memory, or a release-ready model ranking. The audit found real gaps in what was measured.

[Original comparison](local-chat-models-2026-11-01.md) ·
[Benchmark guide](../../Benchmarks/Chat/README.md) ·
[Original evidence](data/local-chat-models-2026-11-01.json.gz) ·
[Frozen original corpus](data/local-chat-models-2026-11-01.corpus.json.gz)

## Findings and corrections

### 1. High: the context cases did not prove summary retention

The original history placed the first release code at message 18 and its correction at message 36.
Compaction removed older messages, but the correction and checklist owner remained in the final
raw message list for every model. The answer could be read directly from recent context. A
`compacted: true` flag plus the right answer therefore did not test the claimed retention behavior.

**Corrected:** move both statements into the early history, outside the initial opening excerpt.
Add `retained_context_omits` checks that require the target code/name to be absent from the final
backend request's raw messages. The zero-tool variant can only use its summary/opening and remaining
messages; the app-tool variants can also recover from the archive. Those are different capabilities.
The old archive remains unchanged, and the new corpus has a different hash.

Targeted verification after the build completed: Apple and Qwen 3.5 4B each completed four corrected
cases/five turns, including the zero-tool case. All eight cases passed their checks. Inspection
confirmed the summary retained the target facts, the raw recent messages did not contain them,
and neither model used tools. The ten turns received explicit agent rubric reviews. Apple's
summary also introduced an unsupported open question about the checklist, outside this narrow
retention rubric; this is not a whole-summary faithfulness pass.
[Corrected context evidence](data/chat-context-audit-2026-11-02.json.gz).

This was a focused validation of the audit working tree, identified by its evaluator/resource and
corpus hashes, using the unchanged production inference code. It is not a replacement seven-model
comparison or a latency study. An earlier validation attempt was stopped to avoid overlapping a
build with inference; its partial local logs are excluded from this targeted artifact, not retried
as part of the original ranking. The clean run evaluated every selected case from the beginning.

Even the corrected cases are small: a few facts in 32 prior turns, not weeks of arbitrary chat.
The trace's compaction flag records a summary generation attempt. The production service can fall
back to attributed excerpts, so this flag alone does not establish successful model summarization.

### 2. High: open-ended failures could receive an automated pass

Confirmed examples in the original app-profile receipts:

| Model and case | What passed | What was wrong |
| --- | --- | --- |
| Ministral, `evidence-screenshot-not-live` | No memory write | Claimed the saved Ghostty screenshot was on the user's screen now |
| Qwen 2B, `memory-unknown` | Allowed tools and no writes | Invented a possible neighborhood instead of treating the address as unknown |
| Qwen 2B, `knowledge-explanation` | Included “tilt” | Said Earth's axial tilt changes throughout the year |

Other checks have similar limits. Budget anchors do not prove correct project/amount association;
an answer can contain a fact while negating it. `memory_contains` searches values for a substring:
it does not establish correct ownership, key, provenance or absence of unrelated writes. The
seven actual positive saved facts were inspected separately and were real writes in this run,
but the generic assertion would also accept some wrong future values.
The aggregate behavior-check count also includes routine completion and tool-error checks, some
of which pass without any tool execution. It is not an independent agent-accuracy percentage.

**Corrected interpretation and reporting:** automated checks remain visible as checks. Full-rubric
review is a separate result; unreviewed or uncertain cases remain pending. A reviewer must inspect
the entire task, including unsupported claims, tool use, saved state and evidence attribution.
No keyword blacklist or model-specific output patch was added to disguise these deficiencies.

The original 161 reviews covered 23 of 78 primary turns per model, about 29%. They were by the
coding agent, were not blind independent judgments, and explicitly excluded presentation and some
tool behavior. In particular, the Gemma 26B 23/23 content-review result does not certify its other
55 primary turns or the leaked thought delimiters. Those reviews remain available as scoped
observations; they are not promoted to full-rubric approval.

### 3. High for ranking claims: one pass and a narrow, correlated corpus

The 735 turns are not 735 independent tasks. Tool variants and multiple scenarios reuse the same
names, projects, facts and questions. The four language scenarios all ask the capital of France;
they test a short instruction, not multilingual conversation quality. Tool scaling has only four
tasks, and adding/removing tools changes capabilities as well as count. Apple also changes sampling
between zero tools and tools. No universal optimal tool count follows from these results.

The original case/model order was fixed. Sampling, loading, temperature, thermal conditions and
other desktop work can affect results. No confidence intervals, repeated stability study or
independent held-out evaluation supports fine differences such as 37 versus 39 passing cases.

**Improved:** new runs freeze a seeded shuffled case order, shared by every model, with independent
orders per repeat. The guide calls for repeated candidate comparisons, model-order rotation,
predeclared rubrics and held-out tasks. This reduces a confound; it does not establish statistical
confidence. Three repeats are a starting point for discovering instability, not a statistical guarantee.

### 4. Medium: review binding covered the reply, not the reviewed action

An old semantic review only carried a hash of the reply. Its tool calls, persisted memory,
question or rubric could change without invalidating the review. That is insufficient when the
review says a memory really saved or a retrieval really happened.

**Fixed:** new receipts expose an evidence hash over the observed turn, including input, rubric,
calls, saved facts, errors, sources and requests. Full-rubric reviews bind to this hash and identify
their reviewer and scope. Changed task evidence invalidates the review even if the reply is identical.
Historical reply-only reviews remain explicitly labeled. Hashes detect inconsistent edits; they
are not signatures proving that evidence was never deliberately fabricated.

### 5. Medium: incomplete or unrelated receipts could distort reports

The old report loaded every JSON file under a model's cases directory without verifying the job
inventory. A copied/renamed receipt could inflate coverage. It displayed automated passes over
completed cases, which could make a partial run look perfect even though coverage appeared in an
adjacent column. Resume skipped any existing filename without validating its contents. The native
protocol also accepted some missing/out-of-order turn events.

**Fixed:** freeze full evaluator cases in new run configurations; validate receipt IDs, questions,
rubrics, positions and reply/evidence hashes; recompute their checks; reject duplicates and unknown
files. Resume uses the same validation. Reports use the planned case denominator and show pending
cases separately. The protocol validates sequential turn starts/results and completion counts.
Operator cancellation now leaves an explicit interrupted receipt instead of silently discarding an
admitted case. Missing work is pending, not a measured failure or an implicit success.

The audit found **no duplicate/missing cases or arithmetic discrepancies in the published run**.
These were real harness weaknesses, not an explanation for that run's low model scores.

### 6. Medium: timing and provenance support narrower claims than app responsiveness

The timer begins after the benchmark has prepared/persisted the user request. It records the first
nonempty received text, including preambles or Gemma control tokens, and total service time plus
post-response persistence/inspection. It does not measure UI interaction-to-answer, first useful
sentence, or audible speech. Error turns are excluded from latency percentiles and reported separately.
Cold and warm turns are mixed, the helper is a debug build, and tests ran on one normally used Mac.

The trace captures app-level backend requests and executed tools, not every provider-internal
inference round or Apple's complete private native transcript. Cached/rejected calls are not
executions. These are useful diagnostics, but cannot precisely attribute every internal delay.

**Improved provenance:** new runs fingerprint helper resources/Metal kernels and the worker catalog
bundle in addition to executable hashes and machine/model metadata. The original kernel resources
were not separately frozen and cannot be retroactively claimed pinned. Apple's asset version remains
system-managed even when the OS build is unchanged. Rebuilding binaries during inference is invalid;
validation builds and model runs must be sequential.

## What held up under review

The worker uses production prompts, capability definitions, conversation services, compaction and
native provider adapters. Its backend session IDs prevent reuse across independent cases, while
normal continuation stays active within a scenario. The benchmark does not route inference through
a duplicate Python model implementation.

Gold rules/rubrics are removed before worker plans are constructed. The model receives legitimate
source fixtures and user requests, not expected answers masquerading as instructions. Every case
owns temporary synthetic Vault and conversation stores. Screenshot preflight checks the actual
image-bearing record category. The earlier broken screenshot pilot was excluded in its entirety,
and every model was rerun afterward.

Actual executed calls and saved facts substantiate the reported Apple opt-out/identity corruption
and the smaller models' missing writes. Gemma's returned birthday was present in its search result
before it denied finding it. Those concrete failures remain valid regardless of ranking uncertainty.
Supervised deadlines and process cleanup keep native hangs bounded, and failed turns remain in
the evidence. No production prompting, model routing or inference behavior was changed by this audit.

## Evaluation schedule and acceptance

| When | What to evaluate | Why |
| --- | --- | --- |
| Every harness/protocol change | Deterministic mutation tests, fixture preflight and replay of archived evidence | Catch false passes, dropped failures, stale judgments and mismatched fixtures without inference |
| Every model, prompt or tool-contract change | Focused bounded live-model cases plus general/Vault topic switching | Detect regressions in the changed behavior without a blocking long test |
| Before selecting a default | Frozen matched full suite, repeats, complete rubric review and held-out tasks | Distinguish a reproducible improvement from formatting, chance or tuning to familiar examples |
| Before speed claims | Release builds, separately defined cold/warm conditions, multiple Macs | Measure the experience being promised rather than an incidental first delta |

Still required before a confident default recommendation: broader independent facts and paraphrases,
longer language-specific conversations, reopened-session recall, checkpointed incremental compaction,
full semantic review including failed cases, and repeated matched runs. Memory privacy failures and
visible protocol leakage are separate readiness blockers; an aggregate average must not conceal them.
Define acceptance criteria before those runs, and report disagreements and uncertainty rather than
changing rubrics after seeing an inconvenient answer.

The corrected suite is better suited to regression work. The original report is an exploratory
diagnostic with preserved evidence, not a final model-quality certification.

## Validation of these corrections

`make check` passed: 611 verified selected native test completions across 18 runs, 52 fixture
preflights, architecture boundaries, localization and native helper checks. The final Python suite
passed all 61 tests, including 27 benchmark tests. The regression tests deliberately exercise an
automated false pass, stale task evidence, altered/duplicate receipts, incomplete runs, changed
kernels, out-of-order protocol events, operator interruption and leaked answers in recent context.
Visible GUI tests were not run; this audit does not change production UI or inference code.

The original evidence archive still has SHA-256
`a8ab1cadddb17c3f4d36b8f6a1bda358ceb89265258ac756bd893827037988b9`.
Both the original archive (with its frozen corpus sidecar) and the new targeted context archive
pass the offline audit command. The targeted run's evaluator hash matches the implementation
included with this audit. No full seven-model rerun is claimed.
