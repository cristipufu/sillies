# Local Chat models: reviewed release-build comparison

This comparison measures the configuration Sillies actually uses: the model, native runtime,
conversation prompts, five local tools, persistent memories, Vault retrieval and context compaction.
It is a test of these integrations, not a model's maximum capability on a general leaderboard.
The shorter [model selection table](../local-text-models.md#which-model-should-i-use) is for choosing
what to download.

## Results at a glance

**Gemma 4 26B A4B had the highest reviewed task score: 70/74 (94.6%).** It also had the slowest median first text in this run. Qwen3.5 4B was a useful smaller compromise: 52/74 (70.3%) at less than half that median latency. Differences of one or two cases between 4B, 9B and Ministral do not establish a meaningful quality ranking.

| Model | Reviewed tasks | Score / 100 | Automated checks passed | Error turns / 107 |
| --- | --- | --- | --- | --- |
| Gemma 4 26B A4B | 70/74 | 94.6 | 71/74 | 0 |
| Ministral 3 8B | 54/74 | 73.0 | 59/74 | 0 |
| Qwen3.5 9B | 53/74 | 71.6 | 56/74 | 1 |
| Qwen3.5 4B | 52/74 | 70.3 | 57/74 | 0 |
| Gemma 4 E4B | 47/74 | 63.5 | 51/74 | 0 |
| Qwen3.5 2B | 30/74 | 40.5 | 38/74 | 0 |
| Apple Intelligence | 17/74 | 23.0 | 22/74 | 11 |

Every primary turn is reviewed: **107/107 per model, 749/749 overall**. Errors and failed tasks remain in the denominator. This is an unweighted scenario score; a multi-turn scenario fails if any turn fails.

Even the highest-scoring configuration has specific remaining failures:

- `memory-correction`: saves the corrected name under a different key and leaves the old name intact.
- `identity-not-user-birthday`: fails to use the available birthday when distinguishing the human from the mascot.
- `mixed-combined-question` and `mixed-paris-meaning`: answers or searches part of the request but misses the needed Vault lookup.

These are observed model/action failures, not claims that a deterministic output filter could repair
arbitrary answers. The raw evidence makes them regression cases for future contract or model changes.

### Scores by task group

| Group | Apple | Qwen 2B | Qwen 4B | Qwen 9B | Gemma E4B | Ministral 8B | Gemma 26B |
| --- | --- | --- | --- | --- | --- | --- | --- |
| context | 3/4 | 0/4 | 4/4 | 4/4 | 4/4 | 4/4 | 4/4 |
| evidence | 1/4 | 1/4 | 2/4 | 3/4 | 2/4 | 3/4 | 4/4 |
| general-knowledge | 0/15 | 8/15 | 14/15 | 15/15 | 14/15 | 14/15 | 15/15 |
| identity | 1/6 | 2/6 | 2/6 | 3/6 | 2/6 | 3/6 | 5/6 |
| memories | 5/16 | 7/16 | 9/16 | 6/16 | 8/16 | 8/16 | 15/16 |
| mixed-knowledge | 2/10 | 4/10 | 6/10 | 7/10 | 4/10 | 7/10 | 8/10 |
| multilingual | 0/4 | 2/4 | 4/4 | 4/4 | 4/4 | 4/4 | 4/4 |
| tool-scaling | 1/4 | 2/4 | 3/4 | 3/4 | 2/4 | 3/4 | 4/4 |
| vault | 4/11 | 4/11 | 8/11 | 8/11 | 7/11 | 8/11 | 11/11 |

Identity scenarios can fail because the human name was never persisted, even when the mascot states its own name correctly. General-knowledge scores also include tool routing and requested formatting; they are not isolated factual-recall scores.

### Memory actions and unwanted saves

| Model | Reviewed save/correction turns | No-write turns with an executed save call |
| --- | --- | --- |
| Gemma 4 26B A4B | 8/9 | 0/53 |
| Ministral 3 8B | 0/9 | 0/53 |
| Qwen3.5 9B | 1/9 | 0/53 |
| Qwen3.5 4B | 1/9 | 0/53 |
| Gemma 4 E4B | 0/9 | 0/53 |
| Qwen3.5 2B | 0/9 | 0/53 |
| Apple Intelligence | 3/9 | 6/53 |

The nine save/correction turns require a memory value and allow a write. Later recall turns are excluded. A pass needs the expected stored state and a passing rubric review, including provenance. The second column counts executed `save_memory` calls on turns whose checks forbid writes, including unsuccessful tool executions; it is not a privacy-success percentage. Other errors remain in the task scores.

Apple made six unwanted save calls. The smaller downloaded models mostly avoided unwanted writes but also failed to save facts they should remember. Even Gemma 26B and Ministral sometimes wrote a corrected name under `user_name` while leaving the old `name` value in place. A fluent confirmation did not make that correction pass.

### Release-build latency

Completed turns without runtime errors, including incorrect answers; first text can be a preamble.
The sample count excludes error turns, not slow completed answers.

| Model | Timed turns | First text p50 / p95 | Whole turn p50 / p95 | Correct short-answer first text p50 (n) |
| --- | --- | --- | --- | --- |
| Gemma 4 26B A4B | 107/107 | 4.92 / 19.46 s | 5.31 / 19.70 s | 4.12 s (44) |
| Ministral 3 8B | 107/107 | 3.98 / 15.87 s | 4.99 / 16.61 s | 3.50 s (41) |
| Qwen3.5 9B | 106/107 | 4.07 / 14.37 s | 4.98 / 15.84 s | 4.07 s (40) |
| Qwen3.5 4B | 107/107 | 2.22 / 7.34 s | 2.71 / 9.98 s | 2.20 s (41) |
| Gemma 4 E4B | 107/107 | 1.16 / 5.58 s | 1.55 / 5.61 s | 1.18 s (41) |
| Qwen3.5 2B | 107/107 | 0.76 / 3.29 s | 0.96 / 3.92 s | 0.76 s (20) |
| Apple Intelligence | 96/107 | 2.07 / 7.73 s | 2.28 / 7.76 s | 1.00 s (16) |

The last column is conditional on a reviewed, correct exact answer. It measures the first alphanumeric streamed answer text, excluding whitespace. Models have different eligible subsets, so it must not replace the all-task comparison or hide failures. TTS and UI rendering are outside these measurements.

### Checkpoint reuse

| Model | Summary calls, turns 1 / 2 / 3 | Time spent summarizing, turns 1 / 2 / 3 |
| --- | --- | --- |
| Gemma 4 26B A4B | 3 / 0 / 0 | 6.75 / 0.00 / 0.00 s |
| Ministral 3 8B | 3 / 0 / 0 | 9.24 / 0.00 / 0.00 s |
| Qwen3.5 9B | 3 / 0 / 0 | 10.90 / 0.00 / 0.00 s |
| Qwen3.5 4B | 3 / 0 / 0 | 5.52 / 0.00 / 0.00 s |
| Gemma 4 E4B | 3 / 0 / 0 | 6.12 / 0.00 / 0.00 s |
| Qwen3.5 2B | 3 / 0 / 0 | 2.93 / 0.00 / 0.00 s |
| Apple Intelligence | 3 / 2 / 3 | 5.54 / 7.22 / 11.71 s |

All downloaded models avoided additional summary calls on the next two turns. Qwen 2B still lost the original code and checklist owner: low cost alone is not successful continuity. Apple retained the requested facts but exceeded the third-turn call budget and ignored the exact-answer formatting. Its later summary inputs advance through old turns that had not yet been compacted; this is not evidence of replaying the entire original backlog.

### Repeated extension cases

The same 22 scenarios ran three times: the initial full pass and two additional passes. These
numbers use **automated checks only**, not the full rubric review used in the main score.
Each pass contains 29 turns. Failures and errors stay in the denominator.

| Model | Pass 1 | Pass 2 | Pass 3 | Passed all three | Changed outcome | Error turns, passes 1 / 2 / 3 |
| --- | --- | --- | --- | --- | --- | --- |
| Gemma 4 26B A4B | 22/22 | 22/22 | 22/22 | 22/22 | 0 | 0 / 0 / 0 |
| Ministral 3 8B | 20/22 | 20/22 | 17/22 | 17/22 | 3 | 0 / 0 / 1 |
| Qwen3.5 9B | 16/22 | 20/22 | 19/22 | 16/22 | 4 | 1 / 0 / 0 |
| Qwen3.5 4B | 16/22 | 17/22 | 17/22 | 16/22 | 1 | 0 / 0 / 0 |
| Gemma 4 E4B | 16/22 | 16/22 | 16/22 | 15/22 | 2 | 0 / 0 / 0 |
| Qwen3.5 2B | 11/22 | 13/22 | 11/22 | 9/22 | 7 | 0 / 1 / 0 |
| Apple Intelligence | 9/22 | 9/22 | 9/22 | 9/22 | 0 | 1 / 1 / 1 |

“Changed outcome” counts scenarios whose pass/fail result differed across the three observations.
Gemma E4B's equal totals hide different failures: the full-record lookup improved while the meeting
owner lookup regressed. Apple's unchanged results reflect stability of both passes and failures,
not high quality. Gemma 26B passed this extension's checks consistently, but that does not erase
its four failures elsewhere in the primary corpus or certify the unreviewed repeated answers.

## What changed before this comparison

- **Reasoning channels:** the MLX adapter separates native private channels before text reaches
  streaming, saved replies or speech. It preserves the model's native message generator and private
  state within a tool turn, then omits that state on the next user turn. Tests cover split delimiters,
  primed and unfinished reasoning, multiple blocks, IPC and template round trips. Gemma 4 follows
  [Google's documented channel and tool-turn conventions](https://ai.google.dev/gemma/docs/core/prompt-formatting-gemma4).
- **Memory and identity:** instructions distinguish the human from the mascot, describe when a
  lasting fact should be saved, and require a real write before acknowledging persistence. Provenance
  binds to the original current user statement in application code. These contracts improve the
  integration; they do not guarantee that a model makes the right storage decision.
- **Retrieval:** conversation search excludes the question currently being answered before ranking
  and limiting results. Tool contracts distinguish older companion chats from saved meetings, and
  explain when a search excerpt requires a record read. Record reads prioritize captured bodies
  over matching titles and generated summaries, including text late in a Stash item.
- **Measurement:** 22 additional scenarios broaden phrasing, facts, opt-outs, mixed questions and
  full-record reads. Incremental-context cases retain the real checkpoint between turns and count
  summarizer calls. Timestamped text emissions distinguish initial feedback from short-answer text.

The existing checkpoint implementation was exercised rather than replaced. No case-specific
semantic output filters or extra routing-model calls were added. The channel parser uses decoded
provider delimiters; literal quoted reserved delimiters remain a documented limitation, not a claim
of token-level parsing fidelity. See the [extension contract](../contributing/chat-tools.md).

The incremental case tests checkpoint reuse and a new correction in recent context. It does not
force that new correction through a second compaction. Separate corrected-code cases do place both
the original and corrected facts outside recent raw messages. A call-budget failure is not itself
proof of replay: Apple's recorded later summary inputs advance through previously unsummarized
workshop turns, while its verbose summary leaves less room for the remaining history.

## How the scores work

The primary comparison gives each model **74 scenarios / 107 turns with the app's five tools**.
A scenario passes only if every turn passes review against its task rubric. Review considers the
answer, executed calls, source evidence, persisted memory and provenance, and relevant context checks.
Fluent acknowledgments without writes do not pass memory-save tasks. Correct answers containing
unsupported additional claims can fail. An answer can also fail an explicit name-only instruction
while containing the right name; the score is task completion, not just factual accuracy.
The frozen rubrics do not grade every aspect of tone or presentation: for example, redundant
Markdown next to a correctly displayed source card is not itself a task failure. Targeted context
recall does not certify every sentence in the intermediate summary.

All primary turns have evidence-bound reviews by the implementing Codex agent. This is **not
independent, blinded or human review**. The reviewer knew the model identity and helped implement
the changes. Judgments and notes are published so others can challenge them. Exact unchanged task
evidence from the diagnostic run can reuse a reviewed judgment after equivalence verification;
changed answers, actions, sources or stored state receive fresh review. Timing and synthetic message
UUIDs are excluded from that equivalence comparison. Original evidence hashes remain in reused
judgments, and the diagnostic archive is retained separately. Of 749 judgments, 118 reuse verified
equivalent diagnostic evidence (102 Apple, 16 Qwen 2B); the rest received fresh review.

Automated checks are reported separately. They test completion, tool behavior, exact answers and
lexical anchors. They cannot establish correctness for open-ended explanations. The reviewed score
does not combine speed and correctness into an arbitrary weighted number.

For example, one Qwen 9B answer correctly names Jupiter but adds that all other planets fit inside
it many times over. Comparing NASA's [Jupiter](https://nssdc.gsfc.nasa.gov/planetary/factsheet/jupiterfact.html)
and [Saturn](https://nssdc.gsfc.nasa.gov/planetary/factsheet/saturnfact.html) volumes shows that Saturn
alone exceeds half Jupiter's volume. A Qwen 4B answer also confuses the lunar orbital period with
the phase cycle; [NASA distinguishes 27.3 days from 29.5 days](https://science.nasa.gov/moon/moon-phases/).
Keyword checks passed both answers; rubric review rejected them. These references inform the review,
not the model prompt.
Review can also accept a lexical false negative: Ministral's `scaling-retrieval` turn returned the
actual saved URL in its displayed source card, although its reply did not repeat the URL. The
automatic text-only check remains failed. Counting an accessible source card as retrieval success
is a stated reviewer interpretation, applied consistently, not a change to the frozen evidence.

### Exploratory tool counts

These four scenarios have the same capabilities at 5, 8 and 12 tools. Extra tools are synthetic
distractors, not production features. This table uses automated checks, including their known
limitations; it is not an additional reviewed score.

| Model | 5 tools | 8 tools | 12 tools |
| --- | --- | --- | --- |
| Gemma 4 26B A4B | 4/4 | 4/4 | 4/4 |
| Ministral 3 8B | 2/4 | 3/4 | 3/4 |
| Qwen3.5 9B | 3/4 | 2/4 | 3/4 |
| Qwen3.5 4B | 3/4 | 3/4 | 3/4 |
| Gemma 4 E4B | 3/4 | 3/4 | 3/4 |
| Qwen3.5 2B | 2/4 | 2/4 | 2/4 |
| Apple Intelligence | 1/4 | 1/4 | 1/4 |

The full pass contains **93 cases / 134 turns per model**, including exploratory profiles with
0, 1, 3, 5, 8 and 12 tools. Only four fixed scenarios vary tool count. The smaller profiles also
remove capabilities, and Apple's no-tool profile changes sampling. Those results do not identify a
universal optimal number of tools.

## Repetition and experimental limits

The 22-scenario extension runs three times per model: once in the full comparison and twice more
with shuffled cases and reversed model order. Additional passes report **automated variability**;
they are not presented as fully reviewed semantic scores. Repeated templates are not independent
questions, and a three-pass result is not a statistical significance claim.

The extension was frozen before its first inference. A diagnostic run then exposed a general
Vault-reader defect: a matching title could hide the captured body. That defect was fixed and the
complete final comparison restarted from a new source commit. The earlier run is excluded from
final scores. The extension is now regression material, not a pristine independent holdout.

The corpus remains small and synthetic, largely English, with a few questions in other languages.
It does not establish quality across every supported language, topic, personal data collection or
conversation length. Chat scores do not certify meeting summaries, dictation cleanup, vision or TTS.
No model default changes as a consequence of this comparison alone.

## Hardware and timing

All final runs use one **Apple M4 Pro, 48 GiB unified memory, 14 logical cores**, macOS **26.7.2
(25G332)**, with release-built workers and the bundled release inference helper. Every downloaded
model uses its pinned 4-bit catalog revision. Apple assets remain system-managed; an unchanged OS
build cannot establish an unchanged asset revision.

Models run sequentially against isolated synthetic databases. The running Sillies app is left
untouched. This is not an otherwise idle laboratory machine: background work, temperatures and
system-managed model state are not controlled. Initial turns may include weight loading, later
turns reuse the runtime, and each bounded batch can start another worker. Results mix these states;
they are neither a controlled cold-start comparison nor a purely warm benchmark.

First-text latency measures the first nonempty streamed delta received by the conversation service.
It may be a preamble such as “I'll search.” It excludes rendering and audible speech. A separate
conditional subset measures the first alphanumeric answer text only for reviewed, correct
exact-answer turns. Completion latency measures the whole turn. Successful-turn percentiles exclude
errors, whose counts remain visible. Timing includes trace and persistence instrumentation.

Apple uses production greedy decoding with tools. Downloaded models use temperature 0.7, top-p 0.9
and repetition penalty 1.08. There is no common fixed random seed. Chat output is capped at 240
tokens; context is bounded by the production service. These are app settings, not each model's
maximum context or output capacity.

RAM figures in the selection table are catalog admission limits, **not measured peak memory**.
Timing on this M4 Pro is not a speed prediction for an M1 or a different-memory Mac. More than one
physical Mac, independently authored tasks and independent human review remain necessary before
making broad release-quality or hardware-performance claims.

## Reproduce and inspect

Runs are headless, offline after installation, and resumable in 180-second admission batches.
Each turn has a 60-second deadline, each case 180 seconds, and worker startup 90 seconds. A batch
stops admitting new cases at its limit; its current case can finish within its separate deadline.
Completed failures are retained rather than retried until they pass. No personal Vault, microphone,
screen capture, app setting or live app build is changed by the benchmark.

See the [benchmark guide](../../Benchmarks/Chat/README.md) for run, export, audit and review commands.
Archives include the frozen corpus, source and binary hashes, model revisions, replies, app backend
requests, tool calls/results, sources, actual memory state, timing and review notes. Audit recomputes
the checks and aggregates from that evidence; it does not certify the evaluator's scientific validity.

The measured source commit is
[`bd35e9a`](https://github.com/cristipufu/sillies/commit/bd35e9a47de535d7ab6df533eec926e1a9e6ed82).
The full corpus hash is `f794423ca136910b87a9a0b3812dcca14426d70fe25747bb1efd31d9849d6b9d`.

| Published evidence | Contents |
| --- | --- |
| [Primary run](data/local-chat-models-2026-11-02.json.gz) | 651 cases / 938 turn outcomes; all 749 primary turns have rubric reviews. |
| [Additional extension passes](data/chat-extension-repeats-2026-11-02.json.gz) | 308 cases / 406 turn outcomes; automated repeat checks. |
| [Derived measurements](data/local-chat-measurements-2026-11-02.json) | Scores, latency, memory actions, tool counts, compaction and repeat variability used in this report. |
| [Excluded diagnostic run](data/chat-models-diagnostic-2026-11-02.json.gz) | Earlier evidence for investigating the Vault-reader fix and tracing reused judgments. Never pooled into the comparison. |

The completed comparison and repeat runs contain **959 case executions / 1,344 turn outcomes**.
Their scores can be reproduced from the published archives without loading a model:

```sh
python3 -B Benchmarks/Chat/benchmark.py audit \
  --archive docs/reports/data/local-chat-models-2026-11-02.json.gz \
  --output build/chat-benchmarks/primary-audit
python3 -B Benchmarks/Chat/benchmark.py audit \
  --archive docs/reports/data/chat-extension-repeats-2026-11-02.json.gz \
  --output build/chat-benchmarks/repeats-audit
python3 -B scripts/summarize-chat-benchmarks.py \
  docs/reports/data/local-chat-models-2026-11-02.json.gz \
  docs/reports/data/chat-extension-repeats-2026-11-02.json.gz \
  --output /tmp/local-chat-measurements.json
diff -u docs/reports/data/local-chat-measurements-2026-11-02.json /tmp/local-chat-measurements.json
```

The last command should show no differences. The summarizer rejects incomplete coverage,
unresolved or stale reviews, and mismatched binaries, model revisions, hardware or repeated fixtures.

Production validation passed `make check` in an isolated build folder: 612 selected native tests,
Python supervisor/scorer tests, all 74 fixture preflights, architecture boundaries and the real
helper protocol/Metal self-check. The final release helper also passed its self-test. Reporting
utilities have additional tests for incomplete reviews, failed repeats, changed run conditions,
answer-timing eligibility, archive reproduction and review equivalence. The final Python suite
passed **81 tests**. No GUI windows were opened.
