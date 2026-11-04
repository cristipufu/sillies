# Prefix caching: state reuse, answer quality and lifecycle

Qwen 3.5 **2B and 4B**, and LFM 2.5 **2.6B**, now enable bounded prefix snapshots.
Gemma 4 26B A4B and LFM 2.5 24B A2B retain their existing policies. Qwen 3.5 9B remains
unqualified by this screen. Ordinary KV caching during generation is used regardless of this policy.

The earlier screen stopped on individual answer differences, sometimes before any state was reused.
This study separates reuse from the numerical effects of splitting a prompt, and reviews improvements
and failures in both arms. It does not claim that caching caused every changed answer, or that a
small sample proves equal quality for all future chats.

## What was tested

The [registered study](../../Benchmarks/Chat/experiments/cache-isolation-2026-11-04/study.json)
compares ordinary processing, split processing with freshly recomputed state, and the same split
with retained state. Identical recorded native requests include questions, tool continuations and
name corrections. Actual serialized token fingerprints must agree. Generated tool IDs are excluded
from content comparisons; tool names, decoded arguments, visible text, errors and private-channel
hashes are included. Private reasoning is not published.

All **72 recomputed/retained output pairs matched** across six models and two sampler seeds,
including 36 warm hits. The ordinary-path repeats matched on all 36 pairs. Native state probes for
the three newly activated profiles also found zero restored-state and restored-logit error.
These are controlled samples, not a proof covering every possible input. Recorded replay inputs
omit archived private reasoning; the separate production workflows exercise actual live tool turns.

The complete conversation comparison contains **288 scenarios / 312 turns**: twelve scenarios per
arm, two seeds, six models. It includes actual memory writes and corrections, opt-outs, hypothetical
and third-party statements, secrets, identity, general knowledge, saved links, full-record retrieval
and mixed questions. Every answer, call and persisted fact was reviewed. These are reused regression
cases, not an independent holdout. Reviews are by the implementing agent, without blinding.

| Model | Reviewed successful turns, ordinary → retained | Uncertain turns, ordinary → retained | Cache decision |
| --- | ---: | ---: | --- |
| Qwen 3.5 2B | 10/26 → 12/26 | 0 → 0 | Enable |
| Qwen 3.5 4B | 16/26 → 18/26 | 0 → 0 | Enable |
| Qwen 3.5 9B | 18/26 → 15/26 | 0 → 1 | Keep disabled |
| LFM 2.5 2.6B | 14/26 → 15/26 | 1 → 1 | Enable |
| LFM 2.5 24B A2B | 19/26 → 19/26 | 2 → 2 | Keep enabled |
| Gemma 4 26B A4B | 22/26 → 22/26 | 0 → 0 | Keep enabled |

The activation margin is no more than five percentage points lost in whole-task success; uncertainty
is not a pass. Scenario totals also satisfy that margin for the enabled profiles. This is a practical
bounded screen, **not a statistical noninferiority result or a new model leaderboard**. Small positive
differences are not evidence that caching improves intelligence.

Automatic checks and semantic judgments remain separate. A correct URL alongside an invented link
count fails review. A friendly name acknowledgment without a write fails. Harmless identity prefaces
can pass semantic review while their exact-format failures remain visible. Third-party retention and
some forward-looking memory claims are marked uncertain where the human-only contract and the
scenario rubric do not establish a clear outcome. No expectation was changed to improve a score.

Qwen 9B's cached replies included a false five-link count, a future-memory claim after an opt-out,
and an unsupported birthday inference posed as a question. The controlled recomputed/retained replays
still matched. Thus its current gate failure is an observed workflow-quality difference, **not evidence
of corrupted saved state**. The misleading whole-Vault count is also an app-contract issue being
addressed separately. Both LFM sizes saved an explicitly opted-out preference in both arms; this
existing memory-decision failure remains visible and is not cured by caching.

## Warm latency and lifecycle

| Newly enabled model | Median first text, rebuilt → retained | Reduction | Retained budget |
| --- | ---: | ---: | --- |
| Qwen 3.5 2B | 1.116 → 0.329 s | 70.5% | 2,048 tokens / 96 MiB |
| Qwen 3.5 4B | 2.779 → 0.780 s | 71.9% | 2,048 tokens / 192 MiB |
| LFM 2.5 2.6B | 1.413 → 0.944 s | 33.2% | 2,048 tokens / 64 MiB |

Each row has ten matched greedy follow-ups with the same correct answers in both arms and real
cache-hit metrics. Initial model loading and prefix creation are excluded; token measurement is
included. The Qwen probes retain the app tool definitions. LFM's timing row uses **direct generation
without tools**, so these rows are not a cross-model ranking or complete tool-loop latency claim.

The original LFM native probe returned tool requests on several samples. That harness cannot execute
tools, and null first-text timestamps are neither zero latency nor completed answers. Those results
remain archived. A declared measurement correction tested the same two arms without tools; the
unchanged full production workflows still assess tool behavior. Its attempted zero-reasoning
exhaustion/recovery control also failed and is not claimed as passed. Native sink-failure,
cancellation and recovery checks use the real production reasoning allowance.

For each newly enabled profile, three native state comparisons, thirteen bounded capacity/release
requests, and native sink-failure/cancellation/recovery checks pass. Changed history, instructions,
tools, session identity, session release and context rejection produce the expected cache reuse or
invalidation. Qwen additionally passes the token-exhaustion recovery control. LFM's eight invalidation
state checks pass, although only two also satisfied that probe's direct-answer condition: its tool
requests and the conflicting assistant history are recorded separately from cache ownership.

The runtime retains one immutable snapshot, not one per conversation turn. Context admission still
measures the complete prompt. Memory pressure and conversation shutdown retain their existing helper
ownership and release paths. No dependency, model template, token stream or native tensor runtime was
patched to obtain the result.

## Limits and reproducibility

Native execution used **3,394.46 of 3,600 registered seconds**, in bounded subprocess batches on one
48 GB M4 Pro. The initial diagnostic mixed sampling configurations inside one helper; this was a
repeatability-fixture defect. Its observations remain archived, followed by the immutable-profile
correction. The registered Gemma byte-cap typo was corrected before any Gemma observation. Both
amendments, input fingerprints, frozen binaries/resources, source overlays, full outputs and native
execution accounting are preserved.

A separate Strata build/test run was detected during part of the conversation comparison. Those
timings do not support a speed claim. The dedicated warm comparisons began after competing Swift
builds/tests and inference helpers had exited. The machine reported no thermal warning. More Macs,
longer chats and independent reviews remain unmeasured by this study.

The SDK's [balanced prefill contract](https://github.com/ml-explore/mlx-swift-lm/blob/3b339ad6e3b3f44c8121ecff5131c7fd55e075e6/Libraries/MLXLMCommon/PrefillParameters.swift)
explains why split and unsplit preparation can differ numerically even without reuse. Exact native
restoration and whole-task review answer different questions; neither replaces the other.

[Evidence and audits](data/cache-isolation-2026-11-04/) include all 24 complete conversation runs,
recomputed objective checks, evidence-bound semantic reviews, diagnostic failures and amendments.
All 24 exports pass the independent recomputation audit. Engineering validation of the final
combined changes is recorded in the [implementation follow-up](cache-memory-followup-2026-11-04.md),
including the passing headless `make check`.
