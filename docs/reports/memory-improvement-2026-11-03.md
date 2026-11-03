# Automatic memory: bounded, model-specific experiments

Status: completed without a qualifying production change. Both models reached the study's stopping
rules. Experimental app changes were reverted; only benchmark acknowledgement timing is retained.
The [preregistered plan](memory-improvement-plan-2026-11-03.md)
and [frozen study](../../Benchmarks/Chat/experiments/memory-2026-11-03/study.json) define the acceptance
criteria and stopping rules; this diagnostic subset does not update the public model leaderboard.

## What the initial comparison found

Baseline is `c49e499ff46f7789348b7b7cfad97b811682ddbd`, including the checkpoint token-suppression fix.
These are reviewed **whole tasks**, including executed tools and actual persisted facts, not fluent
replies or lexical matches. Each screening configuration has one observation per scenario.

| Configuration | Gemma 4 12B | Apple | Finding |
| --- | --- | --- | --- |
| New baseline | 4/6 | 1/6 | Gemma rewrote provenance when answering a birthday question; both missed the preference beside a general question. |
| 1: Required supporting quote | 5/6 | 1/6 | Gemma preserved the birthday source in this pass, but still missed the preference. Apple created duplicate name facts instead of correcting one identity. |
| 2: Separate memory-only tool phase | 2/6 | 0/2 observed; 4 unrun | Gemma still answered the embedded general question during preparation. Apple corrupted correction provenance and attempted a fictional-person write. |
| 4: Separate phase with explicit source and execution ownership | 5/6 | Not targeted | Gemma completed name correction, but the mixed preference task failed at the reasoning-channel boundary twice. |

Apple stopped after two candidates without a useful development signal. Candidate 2 also independently
failed the critical-write rules. The blocked fictional-person write still counts as a critical
attempt; successful storage validation does not turn that decision into a pass. Some cases were
already admitted within the bounded batch before the failure was reviewed; every observed outcome
is retained.

Slot 3 was deliberately skipped. A preparation trace hit its 240-token ceiling in hidden reasoning,
but it had first made an unnecessary lookup for a question. This did not establish that a correct,
required memory operation needed a larger budget. Increasing limits would not address the observed
decision and phase-ownership problems.

The evidence-only strategy was selected as the single Gemma finalist: it tied the refined separate
phase's screening score, adds no inference phase and had no observed protocol error in screening.
The known missed-preference task remains a failure. A small single-pass difference is only a reason
to investigate, not evidence of a reliable improvement.

## Repeated comparison and decision

Candidate and baseline batches alternated against the same development scenarios. On the **eleven
matching observed cases, both passed ten**. The birthday-provenance case also passed twice under the
baseline, so the screening difference does not establish that requiring a quote reliably fixed it.

The finalist missed the lasting preference in “I prefer concise answers. What causes ocean tides?”
in **all three repetitions**. It answered the general question but saved no preference. That violates
the preregistered rule against a scenario failing two of three times. The final batch had admitted
both remaining preference repeats before its results were reviewed; both failures are retained.

| Repeated development run | Observed / planned cases | Reviewed passes | Reviewed failures | Unrun |
| --- | --- | --- | --- | --- |
| Evidence-only finalist | 13/18 | 10 | 3 | 5 |
| Unchanged baseline | 11/18 | 10 | 1 | 7 |

These unequal completed totals are not competing percentages. The extra two finalist observations
are failures of the preference scenario. Once that repeatability gate failed, the remaining repeats,
twelve fresh validation scenarios and six general/Vault latency controls were not run. They remain
unmeasured; there is no qualified latency result or new public model score.

The study used **852.86 seconds (14.2 minutes) of native execution** across 25 bounded batches,
including diagnostic replays, within the 60-minute cap. Three configurations were tried; the
conditional budget-only configuration was skipped for lack of supporting evidence. Exhaustion here
means the agreed experiment and rejection rules were reached, not that either model's capability
ceiling has been established. No additional prompt tuning followed the finalist's failure.

The practical result is to keep the existing production strategy. A supporting quote alone did not
earn a rollout, and an extra memory inference phase did not earn its accuracy or latency cost. The
remaining automatic-memory failures are documented rather than converted into apparent success by
changing the rubric or suppressing outputs.

## Integration investigation

The baseline birthday failure was visible only in the stored state. Gemma answered June 18 correctly,
then saved that same value with the question “Is my birthday April 7?” as its evidence. The tool was
called and the store accepted the current user message; retrieval itself was correct. Requiring a
supporting span verifies where the quoted words came from, not whether those words express a fact
or permission to retain it. No sentence-specific filter was introduced.

Apple's baseline name request produced invented replacement identifiers, which the storage boundary
rejected. Its other traces searched private stores for ordinary knowledge. The separate-phase
experiment did not solve this: one correction retained Maren as the value while changing its source
to the request to use Lior, and another attempted to save a fictional narrator. No incorrect write
was hidden by grading only the final response.

Candidate 2 also introduced an architectural flaw. Preparation calls were archived as if they had
been made by the answering assistant. In a later answer, Gemma requested `save_memory` despite the
answer phase exposing only reads. An exact synthetic replay captured that undeclared call. Candidate
4 assigned preparation exchanges an explicit origin: they remained archived, but were not replayed
as the answer agent's native tool calls. It also supplied the human message as labeled JSON source
data to the preparation worker. Name correction then completed in the observed pass. Because those
changes were tested together, this is not an isolated causal estimate for either change.

The delivered Gemma template contained the complete memory instructions, tools and user text. Its
thinking-disabled suffix matched the checkpoint's empty thought-channel convention. Original roles,
tool results, argument validation, output limits and persisted state were inspected before drawing
conclusions. The remaining malformed reasoning-boundary failures are not a claim that every possible
parser/integration cause has been excluded: normal diagnostics retain failure counts, not the exact
private channel contents. The rejected strategy was not repaired by stripping or guessing tokens.

## Research that informed the experiments

- Apple's [guided generation documentation](https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation)
  explains structured output and property order. Shape constraints do not establish whether a user
  assertion is durable, belongs to the user, or permits saving. The existing native tool path was
  retained rather than introducing a separate community runtime.
- Google's [Gemma function-calling guide](https://ai.google.dev/gemma/docs/capabilities/text/function-calling-gemma4)
  and [prompt protocol](https://ai.google.dev/gemma/docs/core/prompt-formatting-gemma4) informed the
  template and continuation inspection. Gemma's installed template sorts schema property names;
  declaring the quote first in Swift is not proof that Gemma generates it first.
- [LangMem](https://langchain-ai.github.io/langmem/concepts/conceptual_guide/) separates extraction and
  consolidation from conversational answering. [Mem0's paper](https://arxiv.org/abs/2504.19413)
  also describes extraction and update stages. These motivate a separate responsibility, not a
  promise that an additional local inference call will be accurate or responsive. No dependency was
  added, and their reported scores were not treated as results for Sillies.

## Method and limits

The frozen corpus contains six development scenarios, twelve fresh validation scenarios and six
general/Vault controls. Only development cases informed selection. Native release workers run the
production conversation pipeline against temporary synthetic SQLite stores. No real conversation,
Vault, microphone, app preference or window is accessed. Gold checks and rubrics are excluded from
worker input. All 24 fixtures passed preflight before candidate inference.

Candidate declarations, full source snapshots, patches, binary/resource hashes, native requests,
tool results, errors, persisted facts and evidence-bound agent reviews are retained. For example,
“The person speaking is Ivo” is a valid answer to the quoted-narrator question despite missing the
lexical words “narrator” and “character”; its failed lexical check remains visible alongside the
passing semantic review. Reviews are by the implementing agent, not an independent human panel.

Runs use one M4 Pro with 48 GiB on macOS 26.7.2. Model revisions are pinned; Apple's assets are
system-managed. Cases are shuffled with a fixed order seed, which does not seed native generation.
No model work or builds run concurrently. Batches use a separate hard supervisor, cumulative
execution accounting and 60-second turn deadlines. Resumes never replace completed failures.
The shared screening runner's candidate-4 configuration still lists Apple, but its frozen candidate
declaration targets only Gemma and only Gemma was scheduled; Apple's absence there is intentional.

The retained benchmark instrumentation records `memoryCommitSeconds` from the same monotonic start
as text timing. It measures receipt acknowledgement, not SQLite transaction duration, and deduplicates
replayed receipt identities. Older workers have no such field; that is unmeasured, not zero latency.
Preparation output is never counted as visible text. Timing from these short screens is not a
qualified warm-control latency comparison and does not establish a speedup.

## Engineering validation

After restoring production code, `make check BUILD_DIR=/tmp/sillies-memory-study-validation` passed:
707 selected Swift tests across 18 runs, 92 tooling tests, headless presentation checks, the 74-scenario
fixture preflight, formatting and architecture checks, localization extraction, native inference
self-tests, helper parent-exit checks and catalog validation. The candidate-specific tests and final
validation log/receipts are retained separately from model-quality results. Passing these engineering
checks does not qualify the rejected memory strategies.

No app restart, commit or push was performed in this study. The public comparison table is unchanged.

## Evidence

- [Baseline](data/memory-improvement-2026-11-03/baseline-development.json.gz) · [audit](data/memory-improvement-2026-11-03/baseline-development-audit/audit.json).
- [Evidence-bearing writes](data/memory-improvement-2026-11-03/evidence-development.json.gz) · [audit](data/memory-improvement-2026-11-03/evidence-development-audit/audit.json).
- [Separate phase](data/memory-improvement-2026-11-03/separate-development.json.gz) · [audit](data/memory-improvement-2026-11-03/separate-development-audit/audit.json).
- [Refined phase ownership](data/memory-improvement-2026-11-03/boundaries-development.json.gz) · [audit](data/memory-improvement-2026-11-03/boundaries-development-audit/audit.json).
- [Repeated finalist](data/memory-improvement-2026-11-03/finalist-development.json.gz) · [audit](data/memory-improvement-2026-11-03/finalist-development-audit/audit.json).
- [Repeated baseline](data/memory-improvement-2026-11-03/repeated-baseline-development.json.gz) · [audit](data/memory-improvement-2026-11-03/repeated-baseline-development-audit/audit.json).
- [Finalist selection](../../Benchmarks/Chat/experiments/memory-2026-11-03/finalist.json).
- [Final decision](data/memory-improvement-2026-11-03/decision.json).
- [Execution ledger, supervisor, batch logs and native diagnostic inputs](data/memory-improvement-2026-11-03/execution.json.gz).
- [Engineering validation logs and test receipts](data/memory-improvement-2026-11-03/engineering-validation.json.gz).

All candidate implementations are preserved as `candidate-N.patch.gz` plus complete
`candidate-N-sources.json.gz` in the evidence directory. Untracked experimental sources are included
in those snapshots. The source and resource hashes identify the binaries actually used, independently
of later working-tree cleanup.
