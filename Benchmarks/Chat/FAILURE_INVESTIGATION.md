# Investigate the integration before judging a model

A failed Sillies task is evidence of failed end-to-end behavior. It does not identify whether the
model, prompt, runtime, retrieval, storage, or evaluator caused the failure. Parameter count does
not remove the need to investigate; larger models can be constrained by the same app defects.

## Investigation sequence

1. Preserve the original receipt, tool results, model revision, runtime hashes, corpus and build.
   Keep failures in the original score. Do not rerun a case into the same directory until it passes.
2. Check the fixture and rubric against the actual user requirement. Inspect executed writes and
   returned source cards rather than inferring actions from conversational text or lexical anchors.
3. Trace the request through the app. Verify roles, call IDs, tool availability, private reasoning
   state within a tool turn, memory ownership, and what each search or record read actually returned.
4. Inspect native completion and parsing. Distinguish token exhaustion, malformed or rejected tool
   output, context admission, cancellation, transport faults, and a completed but incorrect reply.
   A generic “incomplete response” message cannot establish a cause.
5. Check our limits and recovery. The model must receive meaningful tool results, including empty
   results and partial coverage. A tool budget must not be mistaken for a knowledge limitation.
   Inspect compaction inputs, generated summaries, source fallbacks, and retained checkpoints.
6. Reproduce deterministic defects with an injected provider or actual storage fixture. Replay
   affected real-model cases with the original production path and one changed factor at a time.
   Use repeated observations for stochastic outcomes and retain negative controls and failures.
7. Fix general contracts or lifecycle defects, then run the affected regression cases across
   providers. Freeze a fresh complete comparison before publishing updated recommendations.

## Record the conclusion

For each investigated failure, retain its receipt identity and evidence hash, observed behavior,
inspected code, controlled replay or regression evidence, and one of these conclusions:

| Conclusion | Required evidence |
| --- | --- |
| App or harness defect confirmed | Reproduction identifies a broken invariant, incorrect data, faulty scoring, or missing recovery in our code. |
| Integration-sensitive behavior | A controlled prompt, tool-contract, context, or runtime change affects the outcome; broader validation is still required. |
| Model behavior reproduced under verified conditions | Inputs and runtime behavior were verified and the behavior persisted in bounded controls. State the tested configuration, not a universal model limitation. |
| Unresolved | Evidence is missing, the failure did not reproduce, or several explanations remain. |

A change to the integration starts a new comparison. Historical outcomes remain auditable and
must not be relabeled as model defects merely because their task scores were low. Diagnostic
replays are not an independent held-out evaluation and must not be mixed into the original ranking.

Native diagnostic failures contain reason codes and token/timing measurements, not rejected raw
arguments or private reasoning. The benchmark's synthetic generation-round records preserve
requests, returned tool calls and outputs while omitting private reasoning text; byte counts record
whether that state was present. These diagnostics do not log the user's real conversations.
