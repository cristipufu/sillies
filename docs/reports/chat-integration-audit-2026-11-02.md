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
| Tool-call budget | After four calls, the downloaded-model loop still advertised tools. It now offers an answer-only completion round. A further call receives an explicit not-executed result and one bounded final completion attempt, without touching storage. | All 18 new diagnostic runs completed without runtime errors, but only eight met the full task rubric. Several replies falsely described refused searches as completed. Completion availability does not establish truthful coverage. |
| Native errors | Token-limit stops, rejected tool calls and other incomplete results previously shared one generic error. Diagnostics now preserve reason codes, token counts and content-free response/reasoning byte counts. | Several Gemma 12B failures reproduce as output-token exhaustion. Their underlying cause remains unresolved; increasing the cap alone did not fix the controlled request below. |
| Memory corrections | Writes replace an exact topic key. A correction under `user_name` can coexist with an older `name` entry. | A reliable correction contract that exposes the existing identity and preserves provenance, without name-specific aliases or another heuristic filter. |
| Record reading | An early broad keyword could hide a later passage matching the full query. Reads now rank overlapping passages by distinct query-term coverage and return exact coverage plus an optional continuation offset. | Deterministic regressions pass for later details, query order, Unicode pagination, recovery excerpts and invalid offsets. Bounded real-model follow-up checks are pending. |
| Context admission | Confirmed app defect: a 1,623-token input plus 240 answer tokens and 1,024 reasoning tokens fits the 4,096-token context, but was rejected because of another 1,365-token tool reserve. The final remaining turn can now use available context while retaining a 128-token safety margin. | The six previously rejected LFM turns now reach generation; five pass task checks, while one completes without saving the required memory. Regression tests cover the exact safety boundary, negative counts and integer overflow. |

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

### Comparison with reference implementations

The investigation now includes a minimal native Swift runner using the installed MLX dependencies
and the upstream `prepare` / `generateTokens` workflow. It reuses Sillies' message mapping and local
tokenizer, but bypasses its tool loop, streaming collector, UI and storage. This isolates those app
layers; it is **not** an independent tensor-runtime comparison. Every probe has a 90-second process
deadline and uses the same synthetic captured request and checkpoint.

References inspected:

| Reference | What was checked | Finding for Sillies |
| --- | --- | --- |
| [MLX Swift chat example](https://github.com/ml-explore/mlx-swift-examples/blob/378f2449c257788c5067b9f8b086731d76b39b33/Applications/MLXChatExample/Services/MLXService.swift) | Native input preparation and generation | Provides a small baseline outside the app's orchestration. Its temperature-only sampling setup differs from Sillies' preset. |
| [llama.cpp Gemma adapter](https://github.com/ggml-org/llama.cpp/blob/master/common/parsers/gemma4.cpp) | Tool-result conversion, continuation and native tool grammar | Sillies' installed template already forwards matching tool results. The constrained native tool grammar is a substantive difference from MLX's parse-after-generation path. It has not been ported or tested in Sillies. |
| [Ollama Gemma renderer](https://github.com/ollama/ollama/blob/c1db5f9ef203b2e946161bf4c6bd4f2ec7f123b3/model/renderers/gemma4.go) | Thinking-off prefix and tool-response continuation | The required empty thought block is already present in Sillies' rendered 12B/26B inputs. Adding another block would not repair a missing one. |
| [Google model card](https://ai.google.dev/gemma/docs/core/model_card_4) | Recommended sampling | The documented temperature 1.0, top-p 0.95, top-k 64 preset was tested as a control, without changing app defaults. |

The first ten probes rendered the same 2,027-token input, with prompt SHA-256
`5741dba16433a40ce6bd7d211368a599e37e734d94cfc145d9b5b186a4aa66b9`.

| Native diagnostic configuration | Observations | Result |
| --- | ---: | --- |
| Sillies' sampling, seeds 42/43/44 | 3 | One correct five-token completion; two 240-token channel-marker loops. |
| Google's recommended sampling, same seeds | 3 | One correct five-token completion; two 240-token channel-marker loops. |
| MLX example sampling, seed 42, app's prefill size retained | 1 | 240-token channel-marker loop. |
| Only repetition penalty removed from Sillies' sampling, seed 42 | 1 | 240-token channel-marker loop. |
| Greedy decoding, prefill size 64 | 1 | 60 repetitions of the same four-token empty thought block. |
| Greedy decoding, only prefill size changed to 512 | 1 | The same 240-token output as the previous row. |

These loops are present in the native token stream before Sillies' channel parser. In the greedy
case the model generates empty protocol blocks, explaining why the earlier collector observed zero
response bytes and zero reasoning-content bytes despite exhausting 240 tokens. This rules out the
collector inventing or hiding a successful answer in that reproduction. It does not distinguish
checkpoint behavior, MLX numerical implementation and sensitivity to the supplied conversation.
The observed sampling changes do not establish a reliable fix or a model capability ceiling.

Two further context controls retained the exact existing summary, instructions, tools and current
question, but omitted the 20 recent exchanges. Both returned the correct five-token answer: Sillies'
sampling with seed 43, and greedy decoding. Both had looped with the full history. The shorter input
contained 1,188 tokens. This demonstrates sensitivity to the supplied conversation, but changes both
its length and content. It does not establish that shorter context is always better, or justify dropping
users' recent messages. The summary already contained the needed corrected fact; no gold answer was
inserted. These controls remain separate from the frozen regression case and production policy.

The [native reference archive](data/chat-native-reference-checks-2026-11-02.json.gz) preserves the
twelve configurations, synthetic requests, prompt/output hashes, marker counts, exact scratch-runner
sources and runtime revisions. Private channel text is omitted. No new application dependency,
sampling default, prompt exception or output filter was introduced for these probes.

## Evidence and remaining work

The corrected admission, empty-search and tool-budget implementation passed `make check`: 623
selected tests completed with verified receipts, plus Python checks, packaged native helper checks
and catalog validation. These checks ran headlessly and did not restart the user's app.

A separate release-worker subset exercised seven scenarios / ten turns each on LFM 2.6B, Gemma
12B and Gemma 26B A4B. The six LFM expanded-tool turns previously rejected at admission now all
reach generation. Five pass their task checks; the remaining memory case completes with no write.
Both Gemma models also complete that subset without runtime errors. Empty-result tasks succeed
in this observation, but it does not establish a statistical improvement or replace the preserved
earlier failed result. The task and write outcomes remain in the archive.

A subsequent memory-prompt experiment explicitly required automatic saves and looking up an
existing key before a correction. The first LFM pass covered 19 scenarios / 27 turns, including
opt-outs and secrets. It still missed required saves and persisted a preference despite an explicit
request not to save it. That same opt-out case had no persisted write in the original comparison.
The candidate was **rejected and reverted** before deployment; the planned Gemma passes for that
candidate were not run. This is not proof that the wording alone caused the difference, but the
unwanted write is sufficient to reject it. No keyword filter was added to disguise the failure.

The [contract-check archive](data/chat-contract-checks-2026-11-02.json.gz) preserves the corrected
implementation's 21 scenario receipts and the rejected prompt's 19 receipts, with their distinct
run configurations. None of these targeted observations is included in a published model ranking.

A further tool-limit check used two synthetic scenarios: request four or five separate empty-Vault
searches, then ask a general-knowledge question. Each ran three times on Apple, Gemma 12B and Gemma
26B A4B. With the bounded refusal continuation, all 18 runs completed without a runtime error.
The implementing-agent review checked actual executed searches, refused requests, replies and writes
against the full rubric; it was not independent or blinded. Eight passed. Two Gemma 12B replies
contained malformed tool protocol instead of an answer. Eight of the nine five-search replies
incorrectly implied all five operations completed, although only four executed. The remaining
five-search reply correctly identified the unsearched phrase and answered the general question.
The [tool-refusal archive](data/chat-tool-refusal-checks-2026-11-02.json.gz) preserves all outcomes
and evidence-bound reviews. Its 16 automated passes must not be reported as 16 correct answers.
The archive audit reproduced its recorded checks and metrics. The updated implementation passed
`make check`: 626 selected tests completed with verified receipts, plus the Python checks, native
helper self-tests, fixture validation and catalog checks. All verification was headless.

The subsequent record-passage and optional-parameter schema changes passed `make check` with 630
selected tests and verified receipts. Apple and MLX both preserve optional fields in their native
tool schemas. This validates the retrieval and continuation contract; it does not yet establish how
reliably each model uses it. The native-model receipts above predate that change.

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
