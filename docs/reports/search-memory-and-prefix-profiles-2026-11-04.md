# Search & Memory and prefix-profile qualification — 4 November 2026

The cache decisions below describe the initial screen. The subsequent
[controlled comparison](cache-isolation-2026-11-04.md) supersedes them for Qwen 2B/4B and LFM 2.6B,
separating prompt splitting from state reuse and evaluating whole-task quality in both arms.

This round implements a persistent local memory index and qualifies additional cache profiles.
It does not replace the full chat-model leaderboard or claim that retrieval recall measures
conversational accuracy. All inputs are synthetic; the running app and personal stores were untouched.

## Product implementation

Settings → Search & Memory offers Apple Natural Language by default and an optional
Multilingual E5 Small download. The existing model store handles resumable downloads, verification,
installation leases and removal. E5 uses the already-pinned official native MLX runtime and tokenizer;
there is no Python inference dependency or new package source.

The index lives in `conversations.sqlite`. Updates, corrections, Undo and deletions invalidate vectors
in the same transaction as the fact mutation. In-flight publication checks memory revisions.
Provider replacement cancels and drains old work, rejects stale completion and rebuilds incompatible
spaces. Reopening resumes persisted progress. Index batches, result counts and decoded memory bodies
are bounded; exact scans stream vector rows rather than loading the entire history.

Semantic lookup is optional work with a 150 ms deadline covering embedding and database search.
Cold, busy, unsupported, cancelled and over-budget queries retain keyword search. This is not an ANN
index: large vector collections can exceed the deadline. Interactive inference and speech preempt
background indexing; Apple reasoning participates in admission too. Pause, exclusions, termination,
model removal and memory pressure have explicit shutdown paths. SDKs stay in the helper process;
package checks enforce the app, domain and persistence boundaries.

The scope is **saved companion memories**. Full-archive and Vault search keep their existing indexes.
A semantic candidate is related evidence, not proof that it answers the question. The tool contract
makes that distinction explicit. New-memory creation remains the answer model's responsibility.

See [provider extension and lifecycle contracts](../contributing/search-models.md).

## Production retrieval and answer checks

The final production repository/helper replay used the frozen 76-query corpus. Its validation
partition has 36 positive query variants over 18 facts and 16 deliberately unanswered questions.
The remaining 24 queries are the earlier development partition. This is a reused regression set.

| Search provider | Positive validation recall in top 4 | Negative queries returning candidates | Median lookup, all 76 queries |
| --- | --- | --- | --- |
| Keywords | 31/36 | 13/16 | 0.128 ms |
| Apple contextual + keywords | 32/36 | 15/16 | 9.380 ms |
| Multilingual E5 + keywords | 36/36 | 16/16 | 2.954 ms |

Lookup timing is warm and includes embedding plus repository ranking. It excludes download, initial
model loading, index preparation and reply generation. This tiny corpus is not a large-index latency
claim. Apple had mixed per-query results: it recovered some details but displaced a useful keyword
candidate in the plants query. E5 recovered all positive validation targets. Neither keywords nor
semantic ranking constitutes an answerability classifier: unrelated candidates on negative queries
are why the subsequent source-grounding checks matter.

The separate conversational replay used 16 archived-memory cases: eight answerable questions and
eight missing personal attributes. Original source messages were outside recent context; the
`initial_context_omits` check passed in every case. The selected engine built the real persistent
index in a fresh temporary fixture. The production tool, prompt, context and provider loop then
answered, with no injected gold answers or model-based judge.

| Answer model | Search provider | Reviewed pass | Fail | Uncertain |
| --- | --- | --- | --- | --- |
| Qwen 3.5 4B | Keywords | 13 | 3 | 0 |
| Qwen 3.5 4B | Apple contextual + keywords | 14 | 1 | 1 |
| Qwen 3.5 4B | Multilingual E5 + keywords | 14 | 0 | 2 |
| Apple language model | Keywords | 5 | 10 | 1 |
| Apple language model | Apple contextual + keywords | 5 | 11 | 0 |
| Apple language model | Multilingual E5 + keywords | 5 | 9 | 2 |

Every one of these 96 turns passed the structural checks (tool execution, no writes, isolated initial
context). Those checks intentionally do not score factual accuracy. The table uses evidence-bound
reviews of the complete answers against actual tool results; exported review totals and automatic
checks are independently recomputed by the audit tool. Uncertainty is not counted as success.

E5 recovered Qwen's quiet-room preference and swimming weekdays. Its coffee answer contained the
correct noon restriction but misread the question's framing; its office-city answer proposed a
related residence city as a question instead of clearly admitting the office city was unknown.
Apple embeddings fixed the quiet-room lookup but still missed swimming. The keyword baseline also
made an unsupported office-location inference. These results do not establish calibrated rejection
of all false matches.

Apple's language model did not consistently benefit from better evidence. In E5 runs, the quiet-room,
swimming, shoe-size and plants facts reached the tool result, yet the model still missed them or
followed them with an empty archive search and denied having the information. Several answers copied
the human's first-person facts as the companion's own. In the two semantic arms a conference-date
question was answered with a badge code instead of an admission of uncertainty. This is a real
remaining limitation, not a passed quality check. Thus the index is useful infrastructure and an
optional retrieval improvement; this round does **not** qualify Apple chat as a dependable memory
agent or demonstrate an end-to-end gain for that answer model.

The investigation checked delivered roles, instructions, tool contracts, results and persisted state.
Apple's cases each used one request, about 2,325–2,330 input tokens, no compaction, no context retry
and no generation error. Source roles remained intact and native tool outputs were preserved. Some
misses came from ranking; others occurred after the correct fact was supplied. Further prompt/tool
representation work may help; no case-specific repair was added to the product or the scores.

The supervised search runs consumed 653.9 of the registered 1,200 seconds. MLX used seed 11 in every
arm; Apple used its production sampling settings. Dynamic tool IDs and one pass per arm still limit
causal and repeatability claims. The implementing agent reviewed the answers without blinding.

## Prefix profiles: no new activation

**Audit clarification:** the profiles below remain disabled pending qualification. This screen did
not establish an overall quality reduction caused by caching. The mandatory gate stopped on
individual differences, including differences before any state was reused. Equal aggregate counts
also do not prove equivalence. Read the observed failures as diagnostic cases, not a conclusion
about a model family's ability to use caching.

| Model | Automatic passing turns, baseline → candidate | Decision |
| --- | --- | --- |
| Qwen 3.5 2B | 5/14 → 5/14 | Keep disabled: a known birthday answer was lost and another turn produced an invalid reasoning boundary. |
| Qwen 3.5 4B | 8/14 → 8/14 | Keep disabled: the candidate omitted the general-knowledge half of a mixed question that the paired baseline answered. |
| Qwen 3.5 9B | 7/14 → 7/14 | Keep disabled: a reply incorrectly described all five Vault records as links; the paired baseline correctly reported one link. |
| LFM 2.5 2.6B | 8/14 → 8/14 | Keep disabled: a name-correction reply confused the human's requested name with the companion's identity. The other arm also failed this case, through a context-limit error. |

Each arm completed six cases / seven turns at each of two native sampler seeds (11 and 29),
using identical instructions, tools, production sampling settings and budgets. Tool results contain
run-specific IDs; first-request comparisons excluding session IDs were identical. The candidate
changes only cache retention. These are repeated cases, not 14 independent tasks, and they do not
support a population-level accuracy claim.

Every arm missed both requested name writes. Therefore this round found **no expected write lost
only by caching**, but also did not establish reliable automatic memory creation. Those misses are
visible in the persisted state and cannot be repaired by counting a friendly acknowledgement as a
successful save. Model-visible instructions and delivered `save_memory` definitions were inspected.
No call was emitted for those first name requests. No parser rejection or persistence refusal
explains those particular omissions.

Full-answer inspection mattered: automatic case totals were unchanged for every model while
individual correctness changed. The 9B false link count is an example of an automatic pass that
still failed the semantic review. Unsupported claims, missing answer parts and failed turns remain
in the archived evidence. The implementing agent reviewed them; there was no independent human or
blinded review.

Qwen 2B's ten matched greedy warm-answer controls were correct in both arms. Median first text,
including token measurement, improved **1.052 → 0.319 seconds (69.7%)**. Initial model loading and
prefix creation are excluded from that warm comparison. This speed gain does not override the
quality gate. The other models stopped after their quality/diagnostic review, so their remaining
warm-timing, capacity, cancellation and invalidation qualification gates are **not passed**.

### Native state investigation

The snapshot was compared with independently computed state under the same split preparation:

| Model | Examined requests | Restored state / logits error | Maximum split-versus-unsplit logit difference |
| --- | --- | --- | --- |
| Qwen 2B | 3 | 0 / 0 | 0.4140625 |
| Qwen 4B | 1 | 0 / 0 | 0.34375 |
| Qwen 9B | 1 | 0 / 0 | 0.375 |
| LFM 2.6B | 1 | 0 / 0 | 0.6171875 |

Repeated restoration also had zero logit error, session release cleared the snapshot, and the
first greedy token matched the unsplit reference in these probes. This rules out state-copy
corruption for the inspected inputs; it does not prove every future turn is correct.

The pinned native runtime uses balanced prefill chunks. Separating a stable prefix changes chunk
sizes and floating-point calculation order, including on the first request before any state reuse.
Same-seed generation can consequently diverge later. The native
[chunking contract](https://github.com/ml-explore/mlx-swift-lm/blob/3b339ad6e3b3f44c8121ecff5131c7fd55e075e6/Libraries/MLXLMCommon/PrefillParameters.swift)
and direct logit measurements support this integration finding. It is not evidence that models
must fail these tasks, or that cached state is missing history.

Existing qualified Gemma 26B and LFM 24B profiles remain as they were before this round. Smaller LFM
can retain its native state too, but has not met the answer-quality acceptance criteria here.
No per-question prompt, output filter or test-specific model setting was added.

### Follow-up audit of the qualification method

All 16 archived runs passed the hash and scorer audit again: 96 scenarios and 112 turns are present,
and their automatic counts reproduce. This validates evidence accounting, not the causal conclusion.
Only Qwen **3.5 2B, 4B and 9B**, plus LFM **2.5 2.6B**, participated in this screen. Ordinary KV caching
during token generation remains in use; the disabled policy concerns retaining prompt state across
generation requests.

Inspecting actual `cachedPromptTokens` changes the interpretation of the highlighted failures:

| Flagged case | State reused in the failing turn? | What the comparison establishes |
| --- | --- | --- |
| Qwen 2B, birthday, seed 29 | No: 0 cached tokens | Different answer on the fresh split-prefill path, not a demonstrated restore failure. |
| Qwen 4B, mixed question, seed 29 | No: 0 cached tokens | The general answer was omitted, but both arms already failed the complete task by missing the Vault lookup. |
| Qwen 9B, saved URLs, seed 11 | Yes: 1,564 cached tokens in the follow-up generation | A false count needs controlled replay. Tool-call IDs differ between runs, and split prefill versus reuse was not isolated. |
| LFM 2.6B, name correction, seed 11 | No: 0 cached tokens | The candidate confused identities; the baseline failed with a context-limit error. Neither completed the task. |

The Qwen 2B reasoning-boundary failure also occurred on an initial request. Thus several highlighted
examples cannot specifically implicate reused state. Native probes found exact restoration against
independent computation with the same split, while the ordinary unsplit path differed numerically.
Two seeds over six reused scenarios, selective unblinded regression reviews, no baseline-versus-baseline
repeatability control and no split-without-retention answer arm are insufficient to estimate a
systematic quality effect. Different phrasing is not a quality failure.

A stronger comparison needs three arms: ordinary uncached processing, identical split processing
with fresh state every time, and the same split with retained state. Recorded-request probes should
use identical serialized tokens and tool results; separate production workflow runs should measure
task success, unsupported claims, actual writes and errors across repeated cases. Report which
requests hit the cache, cold versus warm latency, and cancellation/ownership separately. Review both
improvements and regressions, with a predeclared quality margin and bounded execution budget.
LFM 24B and Gemma 26B should enter the same review: their earlier activation had stronger lifecycle
coverage, but its small quality sample was not a statistical equivalence result either.

## Reproducibility

Both experiments use current reviewed source over commit
`e61c21d16b2d3420b8b8e7001a11649323201e57`, including the earlier uncommitted rounds. This is a
same-source cache comparison, **not a comparison with the published main-branch leaderboard**.
Source overlays, catalogs, worker/helper hashes, sampler launchers, complete outputs and deadlines
are preserved with the evidence. MLX Swift is 0.32.3 and MLX Swift LM is 3.32.3 at the pinned revisions.
The hardware is one 48 GB M4 Pro. Other Macs and broader independent cases remain unmeasured.

The [prefix study](../../Benchmarks/Chat/experiments/prefix-profiles-2026-11-04/study.json)
registered a 3,600-second native limit and one candidate per model. Actual supervised execution was
595.4 seconds; mandatory quality failures stopped qualification before exhausting the time budget.
The [search study](../../Benchmarks/Chat/experiments/search-memory-2026-11-04/study.json) separately
bounds production retrieval and conversational comparisons. The old semantic corpus is reused as
a frozen regression set; it is not a new unseen holdout.

## Final implementation verification

`make check BUILD_DIR=/tmp/sillies-search-final-check` passed: completion receipts verified all
738 selected tests, alongside package boundaries, architecture checks, localization, benchmark
fixtures, native helper self-checks, parent-exit checks and the packaged model catalogs. The test app
was built in a separate directory. Visible activation/stacking checks were not run, and the user's
running app was not restarted.

The Settings navigation test also passed in headless mode with snapshots enabled. The new page was
visually inspected in light and dark appearance at the minimum window size; its provider cards use
the existing Settings styling and scrolling container.

After freezing the inference studies, a lifecycle review tightened ownership of preparation waiting
for interactive inference: stopping a search session now cancels and drains that operation too.
A regression exercises that blocked-admission path without ending the other feature's activity.
Unused package dependencies were removed and vector/batch limits consolidated. These changes do
not alter embedding math, ranking, prompts or cache profiles. The full 96-answer study was not
rerun against them. A final release build replayed all 76 retrieval queries for each search arm:
positive recall remained 31/36, 32/36 and 36/36. That replay is preserved separately from the frozen
study, with its own source and binary hashes.

Evidence:

- [Search outputs and audits](data/search-memory-and-prefix-profiles-2026-11-04/search/): complete
  answers, tool results, persisted state, evidence-bound reviews, retrieval outputs and procedures.
- [Prefix outputs and audits](data/search-memory-and-prefix-profiles-2026-11-04/prefix/): both seeds,
  rejected answers, native state diagnostics, warm controls and frozen runtime provenance.
- [Final verification](data/search-memory-and-prefix-profiles-2026-11-04/verification/): post-lifecycle
  release retrieval replay and required-check completion evidence. Each evidence directory includes
  a SHA-256 manifest.
