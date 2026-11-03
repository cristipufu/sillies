# Memory tools: explicit outcomes and measured decision failures

Follow-up: the [completed evaluation and channel fix](channel-memory-followup-2026-11-03.md) resolves
the protocol issue and finishes the unrun cases below. This report and its interrupted snapshot remain
the original historical record.

Memory writes now acknowledge `saved` or `notSaved` explicitly. Successful responses describe the
actual committed identity, revision, canonical key and value. Small evidence budgets retain a short
success acknowledgement, and recovery reuses the existing write receipt. Refused corrections no
longer suggest retrying as a new fact, which could create a duplicate.

This improves the tool contract. It does **not** establish reliable automatic memory decisions or
implicit archive recall. Native tests still reproduced writes against explicit opt-outs, false claims
of saving, duplicate facts, wrong-source searches and missed lookups. No prompt rewrite or model
configuration change from this investigation is retained.

## Method and findings

Baseline is `5a4c38f928916eec84007fd23455822d761b7fe9`. Frozen release workers use the same native
helper, installed model revisions, profiles and evaluator. Eight frozen scenarios contain fourteen
turns per model, combining the earlier archive controls with saving, correcting, hypothetical facts
and opt-outs. Each turn has a 60-second deadline. Runs are synthetic and do not open user histories.

The implementing agent reviewed replies, executed calls and actual persisted memory, with judgments
bound to response/evidence hashes. This caught automated-check gaps: one Gemma response claimed to
save a declined preference without executing a write; Apple answered a hypothetical month question
by saying it could not find the user's birthday. Neither is a successful end-user experience even
though the no-write checks passed.

| Configuration | Apple: reviewed tasks passed | LFM 2.5 24B | Gemma 4 12B | Decision |
| --- | --- | --- | --- | --- |
| Committed baseline | 2/8 | 6/8 | 3/8 | Preserved control |
| Shorter prompt and tool descriptions, explicit outcomes | 2/8 | 6/8 | 5/8 | Rejected: opt-out violations and duplicate memories remain |
| Stronger instruction hierarchy | 1/8 | 4/8 | Incomplete: 4/8 cases observed | Rejected: no reliable gain; additional recall failures |
| Explicit outcomes only | 1/8 | 6/8 | 4/8 | Retained contract change; no overall accuracy improvement claimed |
| Host-managed read revisions | 1/8 | 5/8 | Incomplete: 3/8 cases observed | Rejected: no demonstrated end-to-end gain; additional recall failures |

These are difficult diagnostic cases, **not updated leaderboard scores or reliability rates**.
There is one observation per case/configuration, no matched sampling seed, and native model behavior
varies even with unchanged initial instructions. Differences cannot establish statistical improvement
or uniquely identify a cause. All failures and incomplete stages remain in the evidence.

### What was investigated before attributing failures to a model

- Native Apple sessions receive complete instructions, tools and original user messages. The provider
  retains native tool entries across valid continuations. Inspection found no dropped opt-out clause.
- A correction trace found the right memory but repeatedly omitted its revision parameter. The
  rejected host-reference experiment moved that bookkeeping into a fresh per-turn scope, preserving
  atomic stale-version checks. Its deterministic tests passed, but native runs still produced duplicate
  facts and new recall misses. The original paired-reference interface remains in production.
- Wrong-source searches and missed lookups were distinguished from missing retrieval evidence.
  Correctly returned archive passages did not always lead to the right answer or memory decision.
- One Gemma response exposed a bare `<|channel>` marker. The current reasoning parser recognizes
  complete thought delimiters and orphaned closing delimiters; this malformed opener remains a
  separate unresolved protocol issue. That response is reviewed as failed, despite its correct fact.

Apple's [tool documentation](https://developer.apple.com/documentation/foundationmodels/tool) makes
names, descriptions and schemas part of the model input. Its
[tool-calling guidance](https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling)
does not guarantee semantic correctness. These findings do not justify a keyword router, special-case
answer filter, blanket forced search or a claim that a model is universally incapable.

## Fresh cases and interrupted broader validation

Six further scenarios, seven turns per model, were frozen before candidate inference. They cover a
new preference combined with a general question, a birthday question that must not overwrite a fact,
a name correction, third-party quotation, a mixed-turn opt-out, and a chat-only search with a tempting
matching Vault record. They were run using the retained outcome-only change.

- **Gemma 4 26B: 5/6 reviewed tasks passed.** It handled the opt-out, correction and source restriction,
  but did not save the declared preference in the mixed general question. This small pass does not
  replace the full comparison or establish a new default.
- **Apple: 1/6 passed.** The birthday question succeeded; other cases included missed saves, identity
  confusion and unnecessary private searches.
- **LFM 2.5 2.6B:** six cases observed; one reviewed pass and one unresolved review. It honored the
  mixed-turn opt-out but added an unverified historical claim. Other cases missed saves/corrections or
  searched outside the requested source.
- **LFM 2.5 24B:** four cases completed, three passed. Another case was interrupted by the operator to
  investigate the user's live Teams meeting; it is not a measured model failure. One case remains unrun.
- **Gemma 4 12B:** this fresh-case pass was not started.

All runs use one M4 Pro with 48 GiB on macOS 26.7.2. Testing a smaller model here is not validation on
an 8/16 GiB Mac. These cases and reviews were authored by the implementing agent; independent human
review and broader hardware validation remain outstanding. Native benchmarking was stopped during
the live meeting investigation; the interrupted receipt is retained rather than silently retried.

## Engineering validation

Three new regressions verify actual committed acknowledgements, refused/stale corrections without
mutation, and acknowledgement preservation plus no duplicate write during context recovery. The
focused run passed seven tests, including existing ownership and provenance checks.

The combined memory and [Teams visibility/HUD fix](teams-bound-visibility-2026-11-03.md) passed the
native suite: **705 selected tests across 18 checked runs**. Full build/helper validation is recorded
in the [validation receipt](data/memory-tool-contracts-2026-11-03/validation.json).
No active recording app was replaced for these checks.

## Evidence

- [Baseline](data/memory-tool-contracts-2026-11-03/baseline.json.gz), [audit](data/memory-tool-contracts-2026-11-03/baseline-audit/audit.json).
- [Shorter prompt experiment](data/memory-tool-contracts-2026-11-03/candidate.json.gz), [audit](data/memory-tool-contracts-2026-11-03/candidate-audit/audit.json).
- [Instruction hierarchy experiment](data/memory-tool-contracts-2026-11-03/priority.json.gz), [audit](data/memory-tool-contracts-2026-11-03/priority-audit/audit.json).
- [Retained outcome-only change](data/memory-tool-contracts-2026-11-03/ack.json.gz), [audit](data/memory-tool-contracts-2026-11-03/ack-audit/audit.json).
- [Host-reference experiment](data/memory-tool-contracts-2026-11-03/references.json.gz), [audit](data/memory-tool-contracts-2026-11-03/references-audit/audit.json).
- [Fresh-case partial run](data/memory-tool-contracts-2026-11-03/heldout-interrupted.json.gz), [audit](data/memory-tool-contracts-2026-11-03/heldout-interrupted-audit/audit.json).

Archives include frozen synthetic cases, native inputs, tool results, persisted facts, failures,
reviews and binary/resource hashes. Private reasoning text is excluded. Rejected patches and source
hashes are kept beside the receipts; they are not production changes. The initial shorter-prompt
experiment's untracked `MemorySaveResponse.swift` is preserved only by hash, so that stage is not a
complete source reproduction package. The later stages' shared response source is included.
Do not merge diagnostic subsets into the published full-corpus ranking or erase the operator
interruption on resume.
