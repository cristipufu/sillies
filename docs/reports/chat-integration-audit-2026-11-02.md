# Chat integration failure investigation

**Status: in progress. The expanded comparison is paused.** Failed tasks are not being attributed
to model capability without investigating Sillies' own behavior first. The existing published scores
remain observations of the app integration used for those runs, not model capability ceilings.

The initial inventory contains 130 turn observations with an automated-check failure or a failing
rubric review across the four completed models and the partial Nemotron run. These are observations
requiring investigation, not 130 established model defects. Original receipts remain unchanged.

## What the code and captured results establish

| Area | Finding | What remains to establish |
| --- | --- | --- |
| Empty Vault search | The response has an empty `records` array and a zero returned count, but still tells the model to read a record for missing details. | Whether an explicit no-match result and accurate coverage contract prevent unnecessary follow-up searches across models. |
| Tool-call budget | After four calls, the downloaded-model loop still advertises tools. Another requested call throws instead of entering an explicit answer-only completion step. | Provider-consistent bounded finalization, including multiple requested calls and preserved evidence. |
| Native errors | Token-limit stops, rejected tool calls and other incomplete results previously shared one generic error. | Controlled replays with reason codes and actual generation measurements; the seven Gemma 12B incomplete-response outcomes are not yet attributed. |
| Memory corrections | Writes replace an exact topic key. A correction under `user_name` can coexist with an older `name` entry. | A reliable correction contract that exposes the existing identity and preserves provenance, without name-specific aliases or another heuristic filter. |
| Record reading | Reads return a bounded passage chosen using the first matching query term. A title match can leave a later requested detail outside that passage. | Query/coverage handling and bounded continuation that make the returned evidence sufficient and its limits explicit. |
| Context admission | Tool-result reserve, generation allowance and mandatory reasoning reserve all reduce the app's fixed context budget. | Separate an app admission limit from a model's ability to select among more tools. |

The empty-search case used four different queries: `lunar elevator`, `elevator`, an empty category
listing, and `lunar`. That sequence alone does not establish an irrational repetition loop.
The original task failed to produce an answer, but our budget handling is part of that outcome.

## Work under way

Native failure details now distinguish output-token exhaustion and tool-parser rejection while
keeping the existing user-facing error text. Synthetic benchmark instrumentation records internal
generation rounds, returned calls and metrics. Private reasoning text is excluded. No prompts,
tool contracts, token limits or sampling settings have been changed for the initial diagnostic
replays. These changes are being validated separately from the preserved comparison artifacts.

The [investigation procedure](../../Benchmarks/Chat/FAILURE_INVESTIGATION.md) defines the evidence
required before assigning a cause. Confirmed fixes will receive deterministic regressions and bounded
real-model checks before a fresh comparison is published. There is no new model recommendation yet.
