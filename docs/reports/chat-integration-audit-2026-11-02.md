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
| Empty Vault search | The response had an empty `records` array and a zero returned count, but still told the model to read a record for missing details. It now identifies a completed no-match search, including the normalized query and category. | Whether this clearer contract reduces unnecessary searches across models; a corrected contract is not proof of improved model behavior. |
| Tool-call budget | After four calls, the downloaded-model loop still advertised tools. It now offers an answer-only completion round. Additional calls receive a bounded, explicit not-executed result without touching storage. | Real-model checks of finalization and native Apple continuation; deterministic tests cover multiple calls in a round, refusal limits, preserved call IDs and rejection of calls during answer-only completion. |
| Native errors | Token-limit stops, rejected tool calls and other incomplete results previously shared one generic error. Diagnostics now preserve reason codes, token counts and content-free response/reasoning byte counts. | Several Gemma 12B failures reproduce as output-token exhaustion. Their underlying cause remains unresolved; increasing the cap alone did not fix the controlled request below. |
| Memory corrections | Writes replace an exact topic key. A correction under `user_name` can coexist with an older `name` entry. | A reliable correction contract that exposes the existing identity and preserves provenance, without name-specific aliases or another heuristic filter. |
| Record reading | Reads return a bounded passage chosen using the first matching query term. A title match can leave a later requested detail outside that passage. | Query/coverage handling and bounded continuation that make the returned evidence sufficient and its limits explicit. |
| Context admission | Confirmed app defect: a 1,623-token input plus 240 answer tokens and 1,024 reasoning tokens fits the 4,096-token context, but was rejected because of another 1,365-token tool reserve. The final remaining turn can now use available context while retaining a 128-token safety margin. | Real-model reruns of the affected expanded-tool cases. Regression tests reproduce the old rejection and cover the exact safety boundary, negative counts and integer overflow. |

The empty-search case used four different queries: `lunar elevator`, `elevator`, an empty category
listing, and `lunar`. That sequence alone does not establish an irrational repetition loop.
The original task failed to produce an answer, but our budget handling is part of that outcome.

## Controlled native investigation

The first diagnostic subset preserves the original app prompts, tool contracts, token caps and
sampling. It covers 12 scenarios and 18 turns each for Gemma 12B and Gemma 26B A4B. The latter
completed all 12 scenarios' automated checks. These are targeted diagnostic observations, not a
new score or an independent comparison; automated passes still need semantic and persisted-state review.

For Gemma 12B's corrected-code case, the compactor successfully retained the corrected value.
The subsequent answer generation, not the summary, failed. Replaying that captured generation
directly through the native helper produced:

| Controlled request | Generated tokens | Observed response bytes | Observed reasoning bytes | Outcome |
| --- | ---: | ---: | ---: | --- |
| Original conversation settings | 240 | 0 | 395 | Output-token limit |
| Only output allowance increased | 1,024 | 0 | 4,931 | Output-token limit |
| App's precise sampling preset, original allowance | 240 | 0 | 0 | Output-token limit |

Byte counts describe the collector's observed channels, not a complete attribution of every raw
token. The precise preset changes temperature, top-p and repetition penalty together; it does not
isolate those controls individually. These single-request probes are diagnostic, not statistical
estimates. No production sampling or answer-token cap was changed.

The native tokenizer inspection yields the same 2,027 input tokens measured during inference.
Its rendered prompt has the documented empty thought block for thinking-off mode and no
thinking-enable marker. The installed EOS IDs include the end-of-turn and tool-response boundaries.
Google documents that larger Gemma variants can still emit a thought channel with thinking
disabled, and added the empty block to reduce this behavior. That documentation does not establish
the cause of this particular failure. See [thinking mode](https://ai.google.dev/gemma/docs/capabilities/thinking)
and [prompt formatting](https://ai.google.dev/gemma/docs/core/prompt-formatting-gemma4).

The remaining investigation must distinguish generation/runtime behavior, prompt interactions,
sampling and channel parsing before assigning responsibility. A larger token cap is not a sufficient
fix, and these observations do not establish a model capability ceiling.

## Evidence and remaining work

The [diagnostic archive](data/chat-integration-diagnostics-2026-11-02.json.gz) contains the 24
scenario receipts, original run metadata, three native generation probes and the tokenizer inspection.
It preserves unsuccessful outcomes as well as successful ones. The raw inputs are synthetic fixtures.

Native failure details now distinguish output-token exhaustion and tool-parser rejection while
keeping the existing user-facing error text. Synthetic benchmark instrumentation records internal
generation rounds, returned calls and metrics. Private reasoning text is excluded. The initial
diagnostic replays used frozen artifacts; app corrections are validated separately. The helper's
explicit `--inspect-tokenizer request.json` command inspects a synthetic request using the standard
message generator without loading model weights or running generation. It is not a capture path
for users' conversations.

The [investigation procedure](../../Benchmarks/Chat/FAILURE_INVESTIGATION.md) defines the evidence
required before assigning a cause. Confirmed fixes will receive deterministic regressions and bounded
real-model checks before a fresh comparison is published. There is no new model recommendation yet.
