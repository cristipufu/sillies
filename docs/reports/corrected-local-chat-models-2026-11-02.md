# Local Chat: corrected thirteen-model comparison

This compares Sillies' actual Chat workflow: ordinary questions, saved-record retrieval, memories,
identity and conversation continuity. It measures the model **and its integration with the app**.
An incorrect answer, missing write or runtime failure stays in the score even when the cause is in
our code. The findings below separate observed behavior from established causes.

The primary comparison has 74 tasks and 107 turns per model, with the app's five tools. Each model
also runs 19 additional tool-profile cases: 93 cases and 134 turns in total. All 1,209 case receipts
are present, and all 1,391 primary turns have evidence-bound rubric reviews. Tool-profile curves
use automated checks and are exploratory.

## Scores and hardware requirements

Rows are ranked by reviewed task score. For selection guidance, see the
[model guide](../local-text-models.md#which-model-should-i-use).

| Model | Model release | Required Mac RAM | Download | Reviewed task score | Median first text |
| --- | --- | --- | --- | --- | --- |
| Gemma 4 26B A4B | [2026-04-02](https://blog.google/innovation-and-ai/technology/developers-tools/gemma-4/) | 32 GB | 15.37 GB | **97.3/100** (72/74) | 5.41 s |
| Gemma 4 12B | [2026-06-03](https://blog.google/innovation-and-ai/technology/developers-tools/introducing-gemma-4-12b/) | 24 GB | 6.77 GB | **83.8/100** (62/74) | 6.22 s |
| Nemotron 3.5 Bolt E4B | [2026-10-23](https://research.nvidia.com/labs/nemotron/NVIDIA-Nemotron-3.5-Bolt-E4B-4GB/) | 24 GB | 7.52 GB | **78.4/100** (58/74) | 1.27 s |
| Granite 4.2 8B | [2026-08-25](https://research.ibm.com/blog/introducing-granite-4-2) | 16 GB | 4.95 GB | **74.3/100** (55/74) | 4.86 s |
| LFM2.5 2.6B | [2026-08-04](https://www.liquid.ai/blog/lfm2-5-2-6b) | 8 GB | 1.60 GB | **74.3/100** (55/74) | 5.30 s |
| LFM2.5 24B A2B | [2026-10-13](https://www.liquid.ai/blog/lfm2-5-24b-a2b) | 32 GB | 13.59 GB | **74.3/100** (55/74) | 9.78 s |
| Ministral 3 8B | [2025-12-02](https://mistral.ai/news/mistral-3) | 24 GB | 5.61 GB | **71.6/100** (53/74) | 4.49 s |
| Qwen3.5 9B | [2026-03-02](https://github.com/QwenLM/Qwen3.8#news) | 24 GB | 5.97 GB | **70.3/100** (52/74) | 5.36 s |
| Gemma 4 E4B | [2026-04-02](https://blog.google/innovation-and-ai/technology/developers-tools/gemma-4/) | 16 GB | 5.18 GB | **66.2/100** (49/74) | 1.38 s |
| Qwen3.5 4B | [2026-03-02](https://github.com/QwenLM/Qwen3.8#news) | 16 GB | 3.05 GB | **63.5/100** (47/74) | 2.37 s |
| Granite 4.2 3B | [2026-08-25](https://research.ibm.com/blog/introducing-granite-4-2) | 8 GB | 2.07 GB | **55.4/100** (41/74) | 2.00 s |
| Qwen3.5 2B | [2026-03-02](https://github.com/QwenLM/Qwen3.8#news) | 8 GB | 1.74 GB | **39.2/100** (29/74) | 0.98 s |
| Apple Intelligence | System-managed | Apple-compatible Mac | System-managed | **24.3/100** (18/74) | 2.28 s |

The release date belongs to the original publisher, not the quantized checkpoint upload. Apple's
asset release is system-managed and unavailable to this benchmark. RAM requirements are the app's
admission limits; every timing here was measured on one M4 Pro with 48 GiB, macOS 26.7.2 (25G332).
These are not measurements on every listed RAM configuration, nor peak-memory guarantees.

Gemma 26B leads this run, including all nine required save/correction turns. Its two failed tasks
miss a saved-project follow-up and fail to explain that a screenshot cannot establish current
screen state. Nemotron responds quickly but completes only one of nine required save/correction
turns. A high overall score or low latency alone does not establish reliable automatic memory.

## What a passing task means

All turns must satisfy their request and rubric. Review considers the reply, executed tool calls,
actual source cards, stored memory and provenance. A promise to remember a name without saving it
fails. A correct answer with an invented supporting claim can fail. Explicit number-only or name-only
requests count too: these scores measure task completion, not isolated world-knowledge recall.

A displayed source card can satisfy a retrieval request even if its URL is not repeated in the
reply. An invented URL or a claim that an image is absent despite a displayed screenshot does not.
No-write cases check actual executions and state; fluent privacy assurances do not override a write.
The rubric does not grade every stylistic preference or certify every intermediate summary sentence.

All reviews are by the implementing agent, not an independent, blinded human reviewer. Some injection
follow-ups retain uncertain judgments because the preceding failed lookup did not
carry the injected note into the next request. Those tasks are already failed; uncertainty is not
converted into a passing turn. Review notes and evidence hashes remain available for inspection.

Five passing turn reviews disagree with literal checks: one date uses a narrow nonbreaking space,
three URL retrievals expose the exact URL in the displayed source card, and one corrected memory
labels the old name explicitly as historical. The original failed checks and review explanations
remain intact. These semantic judgments can be challenged without rerunning inference.

| Model | Context | Evidence | General knowledge | Identity | Memories | Mixed knowledge | Multilingual | Tool scaling | Vault |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Gemma 4 26B A4B | 4/4 | 3/4 | 15/15 | 6/6 | 16/16 | 9/10 | 4/4 | 4/4 | 11/11 |
| Gemma 4 12B | 3/4 | 2/4 | 15/15 | 4/6 | 11/16 | 10/10 | 4/4 | 3/4 | 10/11 |
| Nemotron 3.5 Bolt E4B | 4/4 | 3/4 | 15/15 | 3/6 | 11/16 | 7/10 | 4/4 | 2/4 | 9/11 |
| Granite 4.2 8B | 4/4 | 4/4 | 14/15 | 2/6 | 10/16 | 6/10 | 4/4 | 3/4 | 8/11 |
| LFM2.5 2.6B | 2/4 | 2/4 | 15/15 | 5/6 | 8/16 | 5/10 | 4/4 | 4/4 | 10/11 |
| LFM2.5 24B A2B | 0/4 | 3/4 | 15/15 | 4/6 | 11/16 | 6/10 | 4/4 | 2/4 | 10/11 |
| Ministral 3 8B | 4/4 | 3/4 | 14/15 | 3/6 | 9/16 | 6/10 | 4/4 | 3/4 | 7/11 |
| Qwen3.5 9B | 4/4 | 3/4 | 15/15 | 3/6 | 8/16 | 5/10 | 4/4 | 2/4 | 8/11 |
| Gemma 4 E4B | 4/4 | 2/4 | 15/15 | 2/6 | 8/16 | 5/10 | 4/4 | 3/4 | 6/11 |
| Qwen3.5 4B | 4/4 | 3/4 | 14/15 | 2/6 | 8/16 | 4/10 | 4/4 | 2/4 | 6/11 |
| Granite 4.2 3B | 0/4 | 2/4 | 11/15 | 2/6 | 9/16 | 6/10 | 4/4 | 2/4 | 5/11 |
| Qwen3.5 2B | 0/4 | 0/4 | 11/15 | 2/6 | 5/16 | 4/10 | 1/4 | 2/4 | 4/11 |
| Apple Intelligence | 4/4 | 1/4 | 0/15 | 1/6 | 5/16 | 1/10 | 0/4 | 1/4 | 5/11 |

## Memory behavior

| Model | Reviewed + literal state checks, save/correction turns | No-write turns with an executed save call |
| --- | --- | --- |
| Gemma 4 26B A4B | 9/9 | 0/53 |
| Gemma 4 12B | 6/9 | 1/53 |
| Nemotron 3.5 Bolt E4B | 1/9 | 0/53 |
| Granite 4.2 8B | 1/9 | 0/53 |
| LFM2.5 2.6B | 6/9 | 1/53 |
| LFM2.5 24B A2B | 4/9 | 2/53 |
| Ministral 3 8B | 0/9 | 0/53 |
| Qwen3.5 9B | 0/9 | 0/53 |
| Gemma 4 E4B | 1/9 | 0/53 |
| Qwen3.5 4B | 1/9 | 0/53 |
| Granite 4.2 3B | 1/9 | 0/53 |
| Qwen3.5 2B | 0/9 | 0/53 |
| Apple Intelligence | 3/9 | 5/53 |

The save/correction denominator counts turns that require a persisted value and permit a write,
excluding later recall turns. The no-write column counts executed save calls, including rejected
attempts. Neither metric alone proves safe or useful memory behavior: refusing every save would
avoid unwanted writes while failing the feature. The save column additionally requires the literal
stored-value checks to pass. LFM 24B correctly keeps `Sol (replaces Nora)` as the current name; its
semantic review passes, but the literal old-name-absence check fails. That exception is retained
in the evidence and excluded from this stricter save column.

## Responsiveness

| Model | Completed timed turns | Error entries | First text p50 / p95 | Whole turn p50 / p95 | Correct short-answer first text p50 (n) |
| --- | --- | --- | --- | --- | --- |
| Gemma 4 26B A4B | 107/107 | 0 | 5.41 / 17.45 s | 5.78 / 17.47 s | 4.66 s (44) |
| Gemma 4 12B | 104/107 | 3 | 6.22 / 27.12 s | 7.23 / 27.17 s | 5.47 s (39) |
| Nemotron 3.5 Bolt E4B | 107/107 | 0 | 1.27 / 6.26 s | 1.69 / 6.66 s | 1.26 s (41) |
| Granite 4.2 8B | 107/107 | 0 | 4.86 / 10.96 s | 6.84 / 22.35 s | 5.14 s (39) |
| LFM2.5 2.6B | 102/107 | 5 | 5.30 / 13.83 s | 6.56 / 15.44 s | 3.11 s (40) |
| LFM2.5 24B A2B | 95/107 | 12 | 9.78 / 29.27 s | 10.12 / 29.58 s | 4.63 s (35) |
| Ministral 3 8B | 106/107 | 1 | 4.49 / 17.16 s | 5.43 / 17.64 s | 3.91 s (41) |
| Qwen3.5 9B | 107/107 | 0 | 5.36 / 15.82 s | 7.51 / 21.82 s | 4.88 s (42) |
| Gemma 4 E4B | 106/107 | 1 | 1.38 / 8.75 s | 1.80 / 9.72 s | 1.39 s (41) |
| Qwen3.5 4B | 107/107 | 0 | 2.37 / 8.68 s | 2.80 / 9.54 s | 2.38 s (40) |
| Granite 4.2 3B | 107/107 | 0 | 2.00 / 5.36 s | 2.56 / 9.56 s | 2.07 s (33) |
| Qwen3.5 2B | 106/107 | 1 | 0.98 / 2.99 s | 1.16 / 5.00 s | 0.94 s (22) |
| Apple Intelligence | 102/107 | 5 | 2.28 / 4.00 s | 2.53 / 4.45 s | 1.20 s (20) |

First text can be a preamble such as “I'll search.” It is not necessarily a substantive answer or
audible speech. Timing covers the production conversation service and diagnostic instrumentation,
including compaction when needed. Initial loads and reused runtimes are mixed. Error turns stay
in quality scores but are excluded from completed-turn latency quantiles; their count is shown.
A killed case contributes failure entries for later planned turns too; they are not separate observed
native-generation failures. TTS playback and UI rendering are outside these measurements.

Correct short-answer timing is conditional on a reviewed, correct exact answer. It uses the first
alphanumeric streamed text and has a different eligible subset for each model. Do not replace
the all-task comparison with this successful-subset metric.

## App-first failure investigation

Before this comparison, we fixed context admission, bounded tool-limit completion, passage selection
inside long Vault records, and revision-checked memory replacement. See the
[integration investigation](chat-integration-audit-2026-11-02.md). Those targeted diagnostic checks
are separate from this complete comparison and do not replace its failures.

Remaining observed issues include:

- **Granite 3B, lost compacted facts:** three successive native summaries retain the corrected release
  code and checklist owner. The next summary reaches its 320-token output limit. Our fallback keeps
  only the first 600 characters of the previous successful summary; both facts occur later and are
  removed. The final answer does not recover them from the archive. This establishes application
  fallback information loss, not an intrinsic inability of the model to remember the facts. The full
  conversation remains stored.
- **Gemma E4B, empty continuation:** the first generation answers the general question and requests
  the correct meeting. The tool returns the requested owner, and the continuation carries matching
  call IDs and tool results. The transport rejects an empty answer while dropping completion metrics.
  This diagnostic gap leaves the native cause unresolved; the failed task remains in the score.
- **Gemma 12B and LFM 2.6B, malformed tool arguments:** some calls provide a non-UUID record ID or omit a required
  record-read query. Native argument decoding aborts these turns. These expose missing argument
  correction/recovery in the integration; they do not establish a universal model capability limit.
- **LFM 2.6B, long-record lookup:** repeated broad reads miss the requested later passage, followed
  by context recovery and generation exhaustion. The allowance is four tools per attempt with one
  context-recovery attempt; six executed calls across those attempts are not evidence of a new
  global tool-limit bypass.
- **LFM 2.6B and 24B, memory opt-out:** an explicit no-save request still results in a persisted preference for each
  model. A separate opt-out scenario succeeds. Keep the actual unwanted write visible rather than treating
  a successful nearby example as proof of reliable memory policy.
- **LFM 24B, streaming validation:** malformed closing reasoning markers reach the streaming sink
  before final response validation rejects them. This is a confirmed application boundary gap; the
  receipt does not establish why native framing became malformed. Later turns repeat an interrupted-reply
  annotation from the failed history. A separate URL task retrieves the right link but keeps proposing
  calls after the allowance is exhausted, then fails bounded completion. These are distinct failures.
- **LFM 24B, process deadlines:** some context cases exceed the bounded worker deadline before
  returning instrumentation. Their missing stage timings are unknown, not zero; later planned turns
  in a killed case are not independently observed failures. The separate no-tool corrected-code
  case succeeds in 43.38 seconds, including 38.63 seconds in three summaries. The five-tool path
  has a much smaller compaction target under the current app policy. That difference warrants
  measurement; the killed receipts do not prove which stage consumed their time.

Further review findings and exact receipt identities belong in the evidence supplement. None of
these observations was silently retried into a success. No app integration, prompt or evaluator
changes were mixed into the frozen run.

## Context and available tools

| Model | Summary calls, turns 1 / 2 / 3 | Summary time, turns 1 / 2 / 3 |
| --- | --- | --- |
| Gemma 4 26B A4B | 3 / 0 / 0 | 6.83 / 0.00 / 0.00 s |
| Gemma 4 12B | 3 / 0 / 0 | 17.24 / 0.00 / 0.00 s |
| Nemotron 3.5 Bolt E4B | 3 / 0 / 0 | 6.27 / 0.00 / 0.00 s |
| Granite 4.2 8B | 3 / 1 / 0 | 13.48 / 5.39 / 0.00 s |
| LFM2.5 2.6B | 8 / 1 / 1 | 31.22 / 2.41 / 1.08 s |
| LFM2.5 24B A2B | — / — / — | — / — / — s |
| Ministral 3 8B | 3 / 0 / 0 | 12.39 / 0.00 / 0.00 s |
| Qwen3.5 9B | 3 / 1 / 0 | 12.56 / 5.45 / 0.00 s |
| Gemma 4 E4B | 3 / 0 / 0 | 6.35 / 0.00 / 0.00 s |
| Qwen3.5 4B | 3 / 0 / 1 | 5.60 / 0.00 / 1.74 s |
| Granite 4.2 3B | 4 / 0 / 1 | 15.56 / 0.00 / 2.73 s |
| Qwen3.5 2B | 3 / 1 / 0 | 2.89 / 0.51 / 0.00 s |
| Apple Intelligence | 3 / 0 / 0 | 5.75 / 0.00 / 0.00 s |

A dash means no measurement survived, not zero work. Checkpoint call counts describe cost, not
successful continuity. The incremental case reuses the checkpoint across a later correction;
it does not force that correction through a second compaction.
Separate cases place both the old code and its correction before the compaction boundary.

The following tool-count table uses automatic checks; its figures can differ from the reviewed
task scores above.

| Model | 5 tools | 8 tools | 12 tools |
| --- | --- | --- | --- |
| Gemma 4 26B A4B | 4/4 | 4/4 | 4/4 |
| Gemma 4 12B | 2/4 | 4/4 | 3/4 |
| Nemotron 3.5 Bolt E4B | 2/4 | 2/4 | 2/4 |
| Granite 4.2 8B | 3/4 | 3/4 | 3/4 |
| LFM2.5 2.6B | 4/4 | 3/4 | 3/4 |
| LFM2.5 24B A2B | 3/4 | 3/4 | 3/4 |
| Ministral 3 8B | 3/4 | 3/4 | 3/4 |
| Qwen3.5 9B | 3/4 | 3/4 | 3/4 |
| Gemma 4 E4B | 3/4 | 3/4 | 2/4 |
| Qwen3.5 4B | 3/4 | 2/4 | 3/4 |
| Granite 4.2 3B | 2/4 | 3/4 | 3/4 |
| Qwen3.5 2B | 2/4 | 2/4 | 2/4 |
| Apple Intelligence | 1/4 | 1/4 | 1/4 |

The five-, eight- and twelve-tool profiles use the same four scenarios. Extra tools are harmless
synthetic distractors. This is too small a sweep to establish an optimal number of tools. Profiles
with fewer tools deliberately lack capabilities and must not be compared as equally capable agents.

## Conditions and limits

This is **one fresh pass**, not a repeated estimate of model quality. Earlier repeated measurements
used an older integration and remain in their [historical report](local-chat-models-2026-11-02.md).
Their stability does not certify this updated configuration. Case order is reproducibly shuffled;
models run sequentially. Thermal conditions, app activity and cold starts are not controlled enough
to promise small timing differences on another Mac.

The corpus is synthetic and authored by the implementing agent. It has a small set of general facts,
four translations of the same capital question, explicit formatting tasks and deliberately stressful
context fixtures. Previous diagnostic exposure means this is now a regression corpus, not a new
independent held-out test. Broader independent tasks, human review and additional physical Macs are
needed before making general reliability claims. These Chat scores do not establish summarization,
dictation-cleanup, speech-recognition or TTS quality.

The release worker comes from `95ca6aa`; its unchanged native helper comes from `bd08149`. The run
freezes the corpus, evaluator, catalog, resource bundles, installed revisions and executable hashes.
The catalog was later reordered for Settings/README, so remaining batches continued from an exact
source copy verified against the original hashes. No admitted case was interrupted or rerun for
that change. Initial run metadata remains unchanged.

Each model receives a 4,096-token context. Ordinary Chat generation allows 240 output tokens;
mandatory LFM reasoning receives an additional bounded 1,024-token allowance. That is a total
allowance, not a guaranteed private/visible token split. The comparison therefore evaluates shipped
policies, not identical native sampling or output allocations across architectures. Explicit private-channel
text is excluded from published evidence; byte counts and failure metrics remain. Malformed markers
that leaked into the visible stream remain in failed-turn evidence. Successful final generations
without tool calls omit private continuation state, so their zero archived private-state bytes are
not a measurement of zero reasoning work.

Runs use 60-second turn, 180-second case and 90-second startup deadlines. The supervisor stops
admitting cases after each bounded batch and kills overdue worker groups. Timeouts remain failures.
Only synthetic Vault/memory stores are accessed; the user's live records and preferences are not.

## Reproduce and audit

- [Frozen corpus, configuration, receipts and reviews](data/corrected-local-chat-models-2026-11-02.json.gz)
- [Derived measurements](data/corrected-local-chat-measurements-2026-11-02.json)
- [Evidence-bound failure investigations](data/corrected-chat-investigations-2026-11-02.json)
- [Benchmark runner and review procedure](../../Benchmarks/Chat/README.md)

An evidence audit recomputes frozen checks and validates review hashes. It verifies reproducibility
of the stored evidence, not whether every semantic judgment is correct or independent.

```sh
python3 Benchmarks/Chat/benchmark.py audit \
  --archive docs/reports/data/corrected-local-chat-models-2026-11-02.json.gz \
  --output build/chat-benchmarks/audit-corrected-comparison
python3 scripts/summarize-chat-benchmarks.py \
  docs/reports/data/corrected-local-chat-models-2026-11-02.json.gz \
  --output /tmp/sillies-corrected-measurements.json
diff docs/reports/data/corrected-local-chat-measurements-2026-11-02.json \
  /tmp/sillies-corrected-measurements.json
```
