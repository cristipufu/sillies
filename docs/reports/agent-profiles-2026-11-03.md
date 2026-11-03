# Per-model profiles and agent-loop engineering

This report records the earlier profile/compaction implementation. The subsequent
[long-lived conversation work](long-lived-chat-2026-11-03.md) removes summaries from the reply path
and adds cancellable background checkpoints. Measurements below remain historical and unchanged.

This work replaces hidden global inference choices with checkpoint-specific profiles and fixes
application-side context, retrieval and tool-completion behavior. It does not establish a new model
leaderboard. The published [full benchmark](../local-text-models.md) and this focused regression
comparison use different workloads; their latency medians must not be compared as before/after values.

## What changed

- Every downloaded text checkpoint has a required, validated [execution profile](../model-profiles.md):
  declared capacity, application working context, optional native prefill override, independent
  conversation/summary/precise sampling and output allowances, reasoning allowances, and conversation
  budgets. Source configuration URLs and the pinned runtime revision accompany each profile.
- Unset prefill delegates to MLX's model-selected default. The application no longer forces a
  64-token processing chunk. No global 512-token override replaces it.
- Compaction reserves the replacement summary's allowance and continuation headroom before choosing
  the retained suffix. It checkpoints completed work and loads unsummarized history from durable
  storage independently of Chat's visible page. Complete turns remain intact across page boundaries.
- Tool evidence is selected from complete structured representations within measured token budgets.
  Each downloaded-model continuation is admitted against the full serialized request, including
  reasoning state. Apple explicitly delegates its internal tool loop to Foundation Models.
- A selected record's title no longer dominates lexical passage ranking. Requested details take
  precedence; multiple passages can cover separate requested details, with explicit coverage offsets.
- Context recovery replays cached results without a new execution allowance. A verified empty native
  completion after a tool result can preserve text already delivered earlier in the turn. Missing,
  truncated and empty initial completions still fail.

These are generic contracts and algorithms. There are no case-specific prompts, expected-answer
filters, model-name branches in orchestration, or changes to scoring expectations in the original
regression corpus.

## Comparison design

The baseline executable is frozen from `9a4a295`; its application, tests, benchmark source and package
dependencies are identical to committed `1070a01` (the intervening changes are documentation).
Fresh baseline timings are collected beside the candidate on the same Mac, rather than reusing an
older published median. Frozen artifact hashes, resolved profiles, inputs, outputs, native generation
metrics, tool exchanges and actual persisted memory state are retained.

The main comparison covers eight models, twelve existing scenarios, two repeats and 36 turns per
model/variant: 384 cases and 576 turns overall. Cases exercise general knowledge, mixed public/private
questions, screenshot follow-ups after a general-topic detour, saved URLs, later record details,
memory writes and opt-outs, identity, corrections and incremental compaction. The app's five tools are
used unchanged. Model-pair execution order alternates. Inference is sequential, without simultaneous
compilation; batches are bounded and resumable. Turn/case/startup deadlines are 60/180/90 seconds.

The scenario order seed fixes scheduling, **not model sampling**. All failures remain in the
denominator. Timing includes completed turns only, so error counts must be read alongside it.
First text is the first nonempty visible text emission and can be a tool-use preamble. It is not a
general time-to-correct-answer metric. Correct exact-answer turns have a separately reported timing
subset; native prefill timing is also measured separately.
Every primary turn receives an implementing-agent rubric review checked against its receipt hashes.
This is not independent or blinded human review. Exact-name/code cases require the requested format;
an otherwise correct verbose reply fails that explicit requirement. A verbal promise to remember
does not pass without the required persisted state.

The frozen main candidate predates the final empty-tool-completion, recovery-quota, omission-notice
and combined reasoning/answer replacement-budget fixes. Those receive separate regression validation;
main comparison scores must not be represented as measurements of the later binary. The capacity
experiment uses the later build for both context sizes. Reasoning allowances have one source of
truth in the task profile; backends cannot override an independent, conflicting allowance.

## Main engine comparison

Apple M4 Pro, 48 GiB, macOS 26.7.2 (25G332). Every cell is **baseline → candidate**.
Downloaded working contexts remain 4K in this comparison. Times are seconds.

| Model | Reviewed cases | First text p50 | Completion p50 | Completion p95 | Error turns |
| --- | --- | --- | --- | --- | --- |
| Gemma 4 26B A4B | 24/24 → 23/24 | 8.03 → 3.22 | 8.48 → 3.55 | 14.33 → 11.64 | 0 → 0 |
| LFM2.5 24B A2B | 19/24 → 18/24 | 15.48 → 9.90 | 15.99 → 9.94 | 37.41 → 34.60 | 0 → 1 |
| Gemma 4 12B | 18/24 → 19/24 | 6.81 → 8.61 | 8.31 → 8.76 | 29.03 → 17.58 | 6 → 3 |
| Nemotron Bolt E4B | 18/24 → 18/24 | 1.56 → 1.55 | 2.29 → 2.11 | 5.79 → 6.54 | 1 → 0 |
| Gemma 4 E4B | 14/24 → 14/24 | 1.42 → 1.53 | 2.34 → 2.13 | 6.18 → 6.40 | 0 → 0 |
| Granite 4.2 3B | 17/24 → 18/24 | 1.91 → 1.96 | 5.04 → 2.81 | 16.86 → 7.77 | 0 → 0 |
| Qwen3.5 2B | 8/24 → 7/24 | 1.03 → 0.81 | 1.38 → 1.16 | 3.41 → 3.54 | 0 → 0 |
| Apple Intelligence | 8/24 → 10/24 | 2.46 → 2.41 | 2.59 → 2.46 | 3.71 → 4.23 | 2 → 2 |

These use the repository’s nearest-observation percentile convention (rather than averaging the
two central observations). Failed turns remain in task scores but have no completed-turn latency;
read the error column with the timing columns. First text may be a preamble. The measured quality
changes are mixed, and two repeats do not establish statistical significance. Gemma 12B’s p50
regresses even though its p95 and error count improve. This is not a universal speedup.

The raw-request comparison found 16 identical first-generation prompts per downloaded model.
Median native prefill speedups were 1.74× for Gemma 26B, 2.13× for LFM 24B, and 1.04× for Gemma 12B.
The smaller models ranged from 0.97× to 1.08×. These isolate matching requests, but are still
single-machine measurements; total-turn changes also include different tool choices and compaction.

In the first three-turn continuity repeat, Apple’s summary counts changed from `[1, 1, 1]` to
`[1, 0, 0]`, and Gemma 26B showed the same change. Both retained the requested code correction and
owner. This is checkpoint reuse, not a claim that every long backlog can be summarized in one call.

## Working context comparison and selected profiles

The later, checked build ran six cases / ten turns per model at each context size, once per size.
Three continuity cases contain 192 archived messages; the other cases cover reading a later record
detail, a saved name and a memory opt-out. These are 36 cases / 60 turns overall. Both sizes use
identical executables and task decoding; only the catalog working context changes. These separately
declared continuity cases allow correct recall from raw history, checkpoints or archive retrieval.

| Model | Reviewed cases, 4K → 8K | Error turns, 4K → 8K | Completion p50, 4K → 8K | Peak active MLX GiB, 4K → 8K | Selected context |
| --- | --- | --- | --- | --- | --- |
| LFM2.5 24B A2B | 5/6 → 5/6 | 0 → 0 | 14.36 → 6.27 s | 13.129 → 13.159 | 8K |
| Gemma 4 26B A4B | 6/6 → 6/6 | 0 → 0 | 3.31 → 8.67 s | 14.291 → 14.291 | 4K |
| Gemma 4 12B | 2/6 → 5/6 | 5 → 0 | 8.87 → 22.49 s | 7.246 → 7.437 | 8K |

Gemma 12B’s apparent p50 increase compares different completed-turn populations: its slow
long-history cases failed at 4K and therefore have no completed latency. At 8K all five recall turns
completed correctly, in about 22.5 seconds each. Both sizes fail the explicit name-only formatting
requirement while preserving the correct identities and saved name. LFM’s remaining failed case
also concerns the name follow-up requirement, not lost persisted memory.

LFM’s three-turn continuity sequence took **52.38, 12.78, 14.36 seconds at 4K**, versus
**7.05, 6.29, 6.27 seconds at 8K**, with correct answers throughout. Across its complete capacity run,
native logs record 15 summary generations / 186.41 seconds at 4K and none at 8K. The extra peak
active allocation was about 31 MiB in this run; that is not a general memory guarantee.

Gemma 26B demonstrates why larger is not always better. Its first continuity answer improved from
15.49 to 8.94 seconds at 8K, but subsequent replies slowed from **3.28/3.31 to 8.80/8.80 seconds**.
The three-turn total was 22.08 seconds at 4K versus 26.54 seconds at 8K. Its compacted context is
cheaper to process repeatedly, so the selected profile retains 4K for continuous chat.

### Forced-compaction boundary controls

An additional case expands the neutral history to 37,392 characters while retaining the same
correction and owner requirements. It forces work beyond the 8K context instead of merely proving
that raw history can fit. The case was declared before running LFM, then reused unchanged for Gemma
12B before choosing its profile. **Both first turns exceeded the 60-second deadline.** Their two
later turns did not run; all three remain failed for case scoring. Neither is reported as a pass.

Native stage logs distinguish this from a missing-history assumption:

- LFM finished two summary generations in **28.69 + 18.76 = 47.45 seconds**, then one conversation
  generation in 4.74 seconds. There was no completed agent reply before the deadline. Its logs do
  not establish why the complete turn did not finish after that generation.
- Gemma 12B finished two summaries in **18.35 + 7.86 = 26.21 seconds**, then began a conversation
  generation with 105 messages which had not completed when the process was stopped.

The selected 8K profiles improve the measured shorter workloads; they **do not resolve latency when
catching up with a much larger unsummarized backlog**. Profile rationales retain that limitation.
The application-side replacement budget and checkpoint fixes are covered by deterministic tests,
but those tests cannot guarantee native model speed or summary quality. No deadline was raised and
no failing receipt was discarded to improve these results.

All other downloaded checkpoints retain their 4K working contexts. Seven downloaded models were
in the main native comparison; the other five receive validated profiles without a new native
performance claim. No model receives a forced prefill chunk size. Task decoding is preserved rather
than claiming that a single comparison established optimal sampling or reasoning allowances.

## Apple token-counting control

The initial candidate measured every tool result using Foundation Models during its native tool
turn. That increased continuation latency. A standalone native probe found approximately 1.12 s
for a warm long-prompt tool turn versus 1.63 s with the intervening count, although the count itself
took about 20 ms. Both transcript counting and plain-prompt counting showed the effect. The exact
internal cause is not observable; cache invalidation is not established by this experiment.

An explicit backend capability now leaves result admission to Apple's native tool loop while
retaining structured byte bounds, the tool-call quota, initial request token measurement and one
context-recovery attempt. In the focused controls, first text for the mountain question returned
from 4.77 s to 2.45 s (baseline 2.46 s); saved URLs from 4.29 s to 2.64 s (baseline 2.62 s).

## Reading the remaining failures

- A wrong category, a title-only read query, and a wrong passage selected for a useful detail query
  are separate failure stages. The passage-ranking fix cannot infer details absent from the tool query.
- Some replies promise to remember without calling the write tool; others provide invalid arguments.
  Actual writes and provenance are inspected separately from fluent acknowledgements.
- In Qwen 2B's corrected-code failure, the new summary contains the correct code and owner, but the
  answer does not use them. The fact was delivered; a missing-history explanation is unsupported.
- Apple's corrected-code summary can repeat low-value source details and omit the code. Archive search
  recovers it in this run, at additional latency. Checkpoint reuse does not guarantee summary quality.
- Gemma 12B's second incremental-compaction repeat retained the correct facts in its summary but
  exhausted the 240-token reply cap on all three turns, with reasoning bytes and no answer bytes.
  Native tokenizer inspection reproduced the exact 1,948-token first prompt and its disabled-thinking
  empty thought prefix; there was no thinking opt-in token. This matches [Google's documented prompt
  contract](https://ai.google.dev/gemma/docs/core/prompt-formatting-gemma4). Incorrect mode selection
  or lost source facts is not supported by this trace; downstream generation behavior remains unresolved.
  Both baseline incremental repeats also exhaust the reply cap on all three turns.
- Nemotron exposed an application transport defect: it wrote a memory after delivering text, then
  completed the tool turn with no additional text. Transport rejected that valid terminal completion.
  The final protocol fix leaves accumulated-text ownership with the conversation loop. Replaying the
  exact recorded synthetic continuation through the final native helper produced a successful empty
  completion with native metrics in all three attempts. Response-validation and conversation-loop
  regressions verify that the earlier reply survives without repeating the write.
- LFM's second corrected-code repeat spent 26.96 s reaching its 2,368-token summary-generation limit
  entirely in reasoning, with no answer bytes. The literal-excerpt fallback then lost the earlier code;
  a later archive search recovered it, completing the turn in 56.97 s. The first repeat timed out with
  only its Vault search retained in the partial trace; its exact stalled stage is unresolved. A
  reasoning allowance is not a hard native reasoning-channel stop. The pinned runtime's generic
  always-on thinking protocol declares no known-safe forced transition, so this change does not
  invent an early `</think>` injection. See the [native protocol contract](https://github.com/ml-explore/mlx-swift-lm/blob/3b339ad6e3b3f44c8121ecff5131c7fd55e075e6/Libraries/MLXLMCommon/ReasoningConfig.swift).

These are integration observations, not claims of fundamental model limitations. Stochastic changes
in tool choice are not proof that the profile refactor improved or worsened reasoning ability.

## Evidence and validation

The [evidence directory](data/agent-profiles-2026-11-03) contains complete comparison archives,
hash-bound rubric reviews, reproducible measurements, frozen build manifests and native control
logs. Main, capacity and boundary experiments remain separate; their scores are not pooled.
The published full-corpus leaderboard is unchanged.

Final code validation passed `make check`: 665 selected Swift tests across 18 test runs, 92 Python checks, architecture,
catalog and localization checks, and the headless native-helper checks. A release application was
also packaged. Regression coverage includes replacement-summary growth, task and reasoning
allowances, history outside the UI page, complete structured evidence, recovery quotas, valid empty
tool completion, profile-triggered runtime reloads and passage ranking. The final selected profile
data passed the same check suite. These checks use headless presentation; the visible GUI suite
was not run. The [validation receipt](data/agent-profiles-2026-11-03/validation.json) records counts
and the full local log's hash.

The architecture and contributor contract are documented in [Model profiles](../model-profiles.md)
and [Adding a text model](../contributing/text-models.md).

## Limits

This is one Mac and a small, previously exposed regression set. It does not certify all languages,
all Mac memory sizes or an optimal profile. The larger-context experiment uses separately declared
continuity cases that permit correct recall from raw history; it does not relax the original cases'
compaction requirements. MLX peak memory is the helper lifetime's peak active device allocation,
not process RSS or a cross-machine memory requirement. Apple does not expose that metric.

The running app was not restarted or used for benchmarking. Validation builds the local app bundle;
benchmarks use separate frozen executables and synthetic storage. No user records or model selections
were changed, and no models were downloaded for these runs.
