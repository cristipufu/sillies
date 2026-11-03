# Bounded memory-improvement experiment

Status: plan recorded before new candidate inference. Baseline:
`c49e499ff46f7789348b7b7cfad97b811682ddbd`, including the checkpoint-suppression fix.
This is a stopping contract for one investigation, not a claim that its targets are already met.

## Goal and scope

Make automatic personal memory dependable without slowing ordinary conversation: save an explicit
lasting user fact, correct the same fact, recall it later, and preserve its original evidence.
Questions, quotations, hypotheticals, retrieved text and explicit opt-outs must not become new user
facts. A spoken confirmation or saved-memory chip must correspond to an actual committed write.

Start with **Gemma 4 12B and Apple**, evaluated independently. They exercise different runtimes and
have observed memory failures. A winner for one model is not enabled for another without validation.
This round does not tune all twelve models, select a new default, or replace the public leaderboard.
Gemma 26B and LFM 24B are the next portability checks after a candidate qualifies, not extra tuning
subjects hidden inside this budget. Untested providers retain their existing strategy.

## Fixed evidence

Before candidate inference, freeze the following inputs, expected state, rubrics and hashes:

- Six existing development scenarios from the preceding memory/settings investigation: a preference
  plus general question, a birthday question, a name correction, third-party quotation, a mixed-turn
  opt-out, and chat-only search with a tempting Vault result.
- Twelve fresh validation scenarios: six positive save/correction/recall tasks and six no-write,
  ownership/provenance tasks. Include distinct facts, paraphrases, languages and mixed general/private
  questions. Keep these out of candidate selection until a finalist is frozen.
- Six existing general/Vault/topic-switching controls, chosen by coverage before running candidates.

Run the same native application pipeline with synthetic temporary stores, pinned models, frozen
release binaries and unchanged evaluator. Record actual tools, committed facts and provenance,
failures and full-rubric reviews. A fluent reply or lexical match alone is insufficient.
Gold expectations never enter the model input. Reviewers must consider the complete task; mark
uncertain judgments pending rather than passing. These agent-authored cases are fresh validation,
not independent human validation or a representative population sample.

Each candidate first receives **one development pass** on its target model(s). Only a finalist
receives the full comparison: **three repetitions per scenario per model**, for both the frozen
baseline and finalist. Report repetitions as repeated observations, not independent new questions.
Use reversed/interleaved configuration order, no concurrent model work, and separate cold startup
from warm-turn timing. Order seeds do not seed native generation. Audit raw failures before blaming
the model. Inspect native input, roles, schema, returned evidence, parsing, budgets and persistence.

## Candidate limit and hypotheses

There are **four candidate configurations total for this round**, not four per model or four per
experiment family. A configuration declares its target models and all per-model differences before
running. A changed prompt, schema, setting or strategy is a new candidate; combining two candidates
also consumes a slot. Stop early if a finalist meets every gate.

| Slot | Hypothesis and experiment |
| --- | --- |
| 1 | **Evidence-bearing writes.** Require a proposed fact to identify its supporting span in the current user statement; validate that reference before mutation. Test whether this improves attribution and prevents re-saving retrieved facts. Matching a span does not prove consent or meaning, so semantic no-write cases remain mandatory. |
| 2 | **A narrow memory-only decision.** Separate `noChange`/create/correct decisions from answering general questions and searching the Vault. Test one bounded inference pass, scoped only to the necessary message and memory evidence. Measure the extra work and cancellation ownership. This is not a rerun of the rejected general source/intent classifier. |
| 3 | **One trace-justified model-budget adjustment.** Only run if the production trace establishes a token/continuation limit obstructing an otherwise correct memory operation. Freeze the specific setting and rationale first. Skip this slot if no such evidence exists; do not launch a sampling sweep. |
| 4 | **One refinement of the strongest remaining hypothesis.** State its predicted observable effect before execution. This is the only refinement slot, including prompt wording changes or combining earlier findings. |

Previous rejected stronger shared prompts, host-managed revision bookkeeping, the Apple general
intent classifier, and blind publisher-sampling substitutions are not fresh hypotheses. Revisit one
only with new causal evidence, and count that revision against these four slots.

No benchmark-word routing, guessed tool names, output stripping, forced channel closing, or weaker
scoring. Keep the shared orchestration generic and choose measured strategies through explicit
model capabilities/policies. Integrate only a qualifying strategy; preserve focused types, explicit
dependencies and lifecycle ownership. A separately proven integration bug can be fixed and tested
without claiming that the automatic-memory goal has been achieved.

## Success gates, assessed separately per model

All gates must pass; improved average accuracy cannot compensate for an unauthorized write.

1. **No critical failures in any observed candidate run:** no opted-out/secret/third-party fact write
   attempts or mutations, no question promoted to a fact, no lost/corrupted provenance, and no claim
   of saving without a successful commit. Correct rollback, stale-revision rejection, cancellation
   and restart behavior must also pass deterministic tests.
2. **At least 95% reviewed memory-task passes** over the 18 memory scenarios repeated three times:
   at least **52/54**. Fresh validation independently needs **35/36**. No scenario may fail two of
   its three repetitions. A task passes only if all its turns and persisted-state requirements pass.
3. **A useful improvement over baseline:** at least ten percentage points of task gain, or at least
   half as many failed memory tasks. If baseline already meets the gates, retain it unless the new
   strategy has a separately measured benefit. A small fluctuation is not a reason to add machinery.
4. **No regression on the six general/Vault controls:** no reduction in reviewed passes, no new
   critical failures, and no baseline-stable scenario failing in two or more candidate repetitions.
5. **Latency stays within budget:** on the fixed controls, warm first-substantive-answer p50 may rise
   by at most `max(250 ms, 10% of baseline)` and p95 by at most `max(500 ms, 15% of baseline)`.
   Report all turns and errors, plus matched correct-turn latency; never count a quick wrong answer
   as a speed improvement. Missing enough correct control observations makes this gate inconclusive.
   Freeze the answer-bearing timing rubric before inference and derive it from timestamped text
   emissions; a greeting or tool-search preamble is not a substantive answer.
   Also report total completion and memory-commit latency. If a candidate defers memory work, it must
   commit within five seconds after the reply, expose success only after commit, and finish the
   recall/correction task correctly; hiding work after the last text token does not evade evaluation.
6. **Engineering checks pass:** required targeted lifecycle/state regressions and `make check`.
   Inference remains off the UI thread and respects interactive admission/cancellation. No visible
   GUI test or live-user-store access is needed for this investigation.

These numerical gates are engineering acceptance criteria for this frozen suite. They do not prove
95% real-world reliability, a zero population error rate, or performance on every Mac.

## Exhaustion and decisions

- Maximum **four candidate configurations** and **60 minutes of aggregate native execution**,
  whichever comes first. Count startup, failed runs, diagnostic probes, repeats and reruns. Use
  resumable batches of at most three minutes and 60-second turn deadlines, with bounded process
  teardown. No unattended multi-hour run. The execution ledger is cumulative across resumes.
- Stop exploring a model after **two consecutive candidates have no useful development signal**.
  A useful signal means at least one previously failed task passes or one critical failure is
  corrected, without a new critical failure or a reduction in development-task passes. Such small
  screening results only decide whether to investigate further; they do not establish success.
- Reject a candidate on any critical violation; do not rerun until it happens to pass. A valid
  changed implementation consumes another slot. Confirmed harness faults are retained as invalid
  runs and repaired, but their execution time still counts and no candidate limit is reset.
- Pick at most **one finalist per model**. A failed fresh validation exhausts that model for this
  round; do not tune on the exposed validation answers and call the set fresh again.
- At the time/attempt cap, unfinished validation is **inconclusive**, never a pass. Stop at the
  budget even if coverage is incomplete. Do not raise thresholds, deadlines or limits mid-round.

The final decision per model is **qualifies**, **exhausted without a qualifying change**, or
**inconclusive because validation is incomplete**. Keep the current production strategy when there
is no qualified replacement and clearly report its known limitations. If automatic saving remains
unreliable, recommend a product choice—such as explicit confirmation or a better-performing model—
rather than silently changing the already requested automatic-memory UX. Broad comparative scores
and other-model rollout require their own declared validation budget after this round.

Next action: freeze the cases and run the new baseline before implementing candidate 1.
