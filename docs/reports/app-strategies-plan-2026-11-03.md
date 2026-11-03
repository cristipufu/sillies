# App-only model experiments — 3 November 2026

This is a bounded retry of application strategies, not model training or a new leaderboard.
The control is commit `c49e499ff46f7789348b7b7cfad97b811682ddbd`, with the existing benchmark's
memory-commit timing instrumentation. Candidate workers are separate frozen release binaries.
The app is not restarted; all inputs and storage are synthetic.

## What previous work already established

| Proposal | Existing evidence | What remains worth testing |
| --- | --- | --- |
| Tool contracts and references | [Memory contracts](memory-tool-contracts-2026-11-03.md), [channel follow-up](channel-memory-followup-2026-11-03.md), and [memory study](memory-improvement-2026-11-03.md). Supporting quotes, host-managed references, classifiers and a separate memory phase did not qualify. | Separate creation from correction, so new facts do not expose optional identity/revision arguments. |
| Background maintenance | [Continuity review](continuity-review-2026-11-03.md): bounded recent context, incremental checkpoints, cancellation and foreground priority are implemented. | Moving inaccurate fact extraction into the background does not establish correctness. Do not repeat the rejected extraction phase under a different scheduler. |
| Proactive evidence | [Archive recall](archive-recall-2026-11-03.md) improved tool-selected retrieval and passage choice. | Supply four recent saved facts as explicitly attributed source data before model-selected searches. Include missing-source, ownership and correction controls. |
| Profiles and runtime | [Execution profiles](agent-profiles-2026-11-03.md), [checkpoint restrictions](checkpoint-generation-settings-2026-11-03.md), and [provider optimization](provider-optimization-2026-11-01.md). Exact tokenization caching and Apple native continuation already ship. Qwen's prior native session probe reused no tokens. | Check native session-cache feasibility on additional architectures; no manual recurrent-cache trimming. |

## Frozen comparisons

The [registration](../../Benchmarks/Chat/experiments/app-strategies-2026-11-03/study.json)
precedes inference. It contains thirteen models, eight development scenarios (nine turns), six
validation scenarios and explicit success/exhaustion rules. The
[memory-context amendment](../../Benchmarks/Chat/experiments/app-strategies-2026-11-03/memory-context-amendment.json)
was frozen before its first inference: four additional controls place facts behind 80 intervening
messages. The original short cases alone can leave seeded facts visible in recent chat.

- **Split writes:** six available tools instead of five. `save_memory` accepts only key/value;
  `replace_memory` requires the existing key, value, identity and revision. Persistence and
  latest-human-message provenance remain owned by the existing writer. Creation still uses the
  existing stable-key upsert; this experiment does not introduce an insert-only database operation.
- **Memory context:** five original tools. Read up to four recent facts from the already bounded
  memory repository; encode them using the same attribution as `search_memories`. They are user-role
  source data, included in admission/token measurement and disposable under context pressure.
  Raw human statements remain the authority for writes. No new extraction call or router is added.
- **Native cache feasibility:** use MLX's public `ChatSession`, its own token ledger and rewind policy.
  Compare a retained conversation with reconstruction, preserving model profiles and checkpoint
  restrictions. This isolates native potential; it is not an app latency claim or permission to
  bypass app lifecycle, cancellation, tool replay or context validation.

## Promotion and stopping

Native execution is capped at 3,600 seconds total, with 180-second supervised batches and 60-second
turn deadlines. Models run sequentially with no concurrent build or inference. Completed failures
are preserved. Critical unwanted write attempts, corrupted provenance or false save acknowledgements
reject a candidate/model after the current admitted batch.

A quality finalist needs at least two additional manually reviewed task passes, no lost baseline
passes and no critical failure. It must then survive two further development repetitions and a
fresh validation comparison. The memory-context screen includes its four declared older-history
controls. No prompt tuning after inspecting results; one repair is permitted only for an actual
integration defect.

A performance promotion requires matched correct warm controls, at least five distinct tasks and
two repetitions per arm. Median improvement must exceed both 10% and 100 ms; p95 may not regress
by more than the larger of 15% and 500 ms. Native feasibility alone does not meet this standard for
an application change. Cold loading is reported separately.

Reviews bind to the complete turn evidence: original inputs, native requests, executed calls,
results, persisted facts and provenance. Lexical check failures may be false negatives; fluent
answers may still fail storage requirements. Reviews here are agent judgments, not independent
human review. Every candidate uses the same frozen scenario definitions as its corresponding
control. Exhaustion, partial coverage and unresolved failure causes remain visible.
