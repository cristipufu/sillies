# LFM Chat: integration fixes and fresh results

This reruns both LFM models after correcting app-side integration problems. The models use the
same pinned weights and the same 74-task corpus as the
[earlier thirteen-model comparison](corrected-local-chat-models-2026-11-02.md). Failed cases remain
in the results; diagnostic replays do not replace them.

Both models complete more reviewed tasks in this pass. **24B rises to 85.1/100; 2.6B rises to
82.4/100.** This does not establish a statistically reliable improvement: several integration
changes were combined, sampling changed, and each build has only one full pass.

| Model | Previous task score | New task score | Previous median first text | New median first text | Previous / new error entries |
| --- | --- | --- | --- | --- | --- |
| LFM2.5 24B A2B | 74.3 (55/74) | **85.1 (63/74)** | 9.78 s | 9.41 s | 12 / 2 |
| LFM2.5 2.6B | 74.3 (55/74) | **82.4 (61/74)** | 5.30 s | 6.46 s | 5 / 1 |

There is **no general speedup claim**. The smaller model's median first text is slower, and long
histories still produce substantial delays. A killed case in the earlier run also contributes
errors for later planned turns; those entries are not separate observed native failures.

| New run | Completed timed turns | First text p50 / p95 | Whole turn p50 / p95 | Correct short-answer first text p50 (n) |
| --- | --- | --- | --- | --- |
| LFM2.5 24B A2B | 105/107 | 9.41 / 31.93 s | 9.65 / 33.54 s | 4.41 s (41) |
| LFM2.5 2.6B | 106/107 | 6.46 / 21.53 s | 6.93 / 23.12 s | 2.35 s (39) |

The short-answer metric includes only correct, reviewed exact-answer turns. Its eligible subset
differs between models; it must not replace all-task latency or hide failures.

| Task group | LFM2.5 24B A2B | LFM2.5 2.6B |
| --- | --- | --- |
| Context | 4/4 | 2/4 |
| Evidence | 2/4 | 3/4 |
| General knowledge | 15/15 | 13/15 |
| Identity | 4/6 | 6/6 |
| Memories | 11/16 | 13/16 |
| Mixed knowledge | 8/10 | 7/10 |
| Multilingual | 4/4 | 4/4 |
| Tool scaling, app profile | 4/4 | 3/4 |
| Vault | 11/11 | 10/11 |

Group labels are not an exhaustive capability partition: the long-record task belongs to Evidence
and a long-history conversation-search task belongs to Mixed knowledge. The 24B 4/4 Context score does
not mean every long-history task passed. Its conversation-search task still timed out.

Required save/correction turns pass both review and literal state checks in **6/9** cases for 24B
(previously 4/9) and **7/9** for 2.6B (previously 6/9). Neither makes an executed save attempt on
the 53 no-write turns in this pass, versus 2 and 1 respectively before. That is encouraging evidence,
not a guarantee of reliable memory consent or corrections.

All **186 case receipts and 214 primary-turn reviews** are present. Automatic task checks pass
66/74 for 24B and 65/74 for 2.6B; semantic review lowers those figures. One passing 2.6B turn
disagrees with a literal tool-execution check: two invalid read arguments are corrected within
the allowance, and the final answer correctly reports 17 tests. The earlier turn in that same
conversation still fails, so the task does not become a pass. Both the failed checks and review
explanation remain in the archive.

## What changed before this run

The release worker and helper were frozen at `9a4a29579bd591eb9223676e1d4f5b350c7deba5`.
The implementation is in `f9d3c57` and `9a4a295`; no inference code, prompts, corpus or evaluator
changed during the scored run.

1. **Publisher sampling.** Both LFMs now use temperature 0.1, top-p 1 and top-k 50. Repetition
   penalty is 1.05 for 24B and 1.1 for 2.6B. These are catalog capabilities, applied to conversation
   and text tasks without model-ID branches. Previously summary tasks used greedy sampling and
   conversation used generic defaults. The settings follow the
   [24B model card](https://huggingface.co/LiquidAI/LFM2.5-24B-A2B) and
   [2.6B model card](https://huggingface.co/LiquidAI/LFM2.5-2.6B).
2. **Capacity-based compaction.** The app measures the largest recent suffix that fits and
   summarizes the preceding complete turns together. The summarizer splits oversized input at
   turn boundaries using actual tokenizer capacity. This removes the fixed four-turn chunking
   that repeatedly summarized long histories. A generated summary can still require another
   reduction; it is not a guarantee of one call.
3. **Summary reasoning allowance.** Always-reasoning models receive 2,048 additional generation
   tokens for history summaries, versus 1,024 for replies and ordinary precise transformations.
   A summary requesting 320 tokens therefore has a combined ceiling of 2,368. Context admission
   and native generation share this policy. The 4,096-token context and benchmark's 60-second
   turn deadline are unchanged. Reasoning and visible output share one ceiling; this does not
   enforce separate channel quotas.
4. **Recoverable tool arguments.** Missing or malformed declared arguments produce a bounded
   `notExecuted` tool result with the offending parameter and remaining allowance. The model can
   correct the call within the existing budget. The call ID is preserved and no operation runs.
   Storage failures and cancellation still propagate; this is not a catch-all error suppression.
5. **Stream framing and interrupted history.** The native reasoning emitter remains responsible
   for channel separation. An unmatched configured closing delimiter is now rejected before that
   delimiter reaches displayed or spoken text, including split chunks. Interruption annotations
   no longer get appended to assistant speech in subsequent model context. Earlier delivered
   text remains interrupted rather than being silently rewritten. This validates framing, not
   the factual quality or provenance of arbitrary generated prose.
6. **Deadline diagnostics.** The benchmark writes content-free generation start/finish events
   before a process deadline can erase an unfinished turn's in-memory instrumentation.

These changes are shared abstractions, not responses keyed to benchmark questions. Existing
models without a sampling preset retain task defaults. Other families have not been rerun on
this build, so the main model guide explicitly identifies its mixed build provenance.

## Why change the summary allowance?

A direct native experiment used the same LFM 24B backend and seed, bypassing the app's tool loop,
storage and output parsing. Both settings received identical prompts within each source size.

| Source | Sampling | Generation ceiling | Generated tokens | Result |
| --- | --- | --- | --- | --- |
| Four turns | Greedy | 1,344 | 1,224 | Finished summary, 15.44 s |
| Four turns | Publisher | 1,344 | 854 | Finished summary, 10.17 s |
| Full history | Greedy | 1,344 | 1,344 | Exhausted allowance before visible summary, 17.81 s |
| Full history | Publisher | 1,344 | 1,344 | Exhausted allowance before visible summary, 19.37 s |
| Full history | Publisher | 2,368 | 1,830 | Finished summary retaining corrected code and owner |

The full source is 1,327 input tokens. Sampling alone did not solve its output exhaustion;
the bounded larger allowance let this particular native generation finish. Native token counts
include the terminating token and can differ by one from helper completion metrics. No duration
was recorded for the final experiment. These are single-seed diagnostic observations, not a
separate accuracy score or evidence that every long history now works.

The stream investigation also reproduced two closing markers after a correctly primed reasoning
prefix. The SDK emitter passed the orphaned second close into the response channel. This rules
out a missing prefix in that reproduction; it does not establish an independent model-weight or
tensor-runtime defect. Six later production-runtime probes with publisher sampling had clean
framing, but those six observations do not prove universal elimination of malformed output.
The protocol regression, rather than a phrase-specific answer filter, protects the streaming sink.

The [diagnostic supplement](data/lfm-chat-investigations-2026-11-02.json) preserves controlled
settings, synthetic summary requests, visible outputs, stage measurements and limitations.
Private reasoning is excluded.

## Remaining problems and what the evidence establishes

- **Long histories can still be slow or fail.** In 24B's `heldout-conversation-versus-vault`, two
  summaries consume about 24.6 and 25.6 seconds and each exhausts 2,368 tokens. The next reply
  starts before the 60-second turn deadline kills the worker. The stage journal has ordering but
  no per-case identifier; the supplement preserves that limitation rather than assigning exact
  case identities to every journal event.
- **A correct answer does not prove a good summary.** The 24B `context-corrected-code` task passes
  after an exhausted summary and a later summary that omits the code: conversation search
  recovers the archived correction. This is successful end-to-end continuity through retrieval,
  not successful summary retention. The smaller model's same task preserves the code in its
  summaries but still makes unnecessary private searches and requires context recovery.
- **Correction results help, but retrieval strategy remains fallible.** The 2.6B model recovers
  missing read arguments in a screenshot follow-up. Both models still fail the long-record detail
  task: calls choose broad or wrong-topic queries and overlapping passages instead of the needed
  later detail. The tool replies describe partial coverage and the available continuation; the
  receipts retain exactly what the model received. These failures do not prove that a different
  tool contract or runtime would have the same outcome.
- **Memory semantics remain unreliable.** Both models can save a new name under a different key
  while leaving the old name active, or acknowledge a fact without saving it. Valid argument
  decoding does not establish a correct memory decision. The earlier opt-out regressions and
  every actual save attempt remain available in the two runs' evidence.
- **Ordinary answers still need semantic review.** The 24B Pacific answer adds the false claim
  that it exceeds all other oceans combined; NOAA gives roughly 45% of ocean area. The 2.6B
  seasonal explanation assigns June summer to both hemispheres. These fail despite matching
  answer keywords. See [NOAA's ocean proportions](https://www.noaa.gov/jetstream/ocean) and
  [NASA's explanation of opposite seasons](https://science.nasa.gov/earth/earth-observatory/an-epic-view-of-the-seasons/).
- **Scope and attribution can still be wrong.** Empty Vault results can be described as absence
  from personal memory or chat without searching those stores. A saved screenshot can be
  mistaken for the current screen. Routing, evidence and source-state claims are reviewed
  independently of fluent wording. In 2.6B's `context-owner`, Mina is present in the summary
  and even quoted in the final reply, yet the model refuses to use it without a Vault match.
  The request permits conversation-based answers. This is an evidence-interpretation failure
  at the prompt/tool boundary, not lost summary content; a clearer contract may still help.

No observed failure is automatically classified as an intrinsic model limitation. This run tests
our current prompts, budgets, retrieval contracts and native adapter together. It is useful for
choosing a Sillies configuration and locating failures, not establishing a model's maximum ability.

## Method and reproducibility

The run uses one M4 Pro with 48 GiB, macOS 26.7.2 (25G332), release binaries, sequential models
(24B then 2.6B), order seed 0 and one fresh pass. Each model has 74 primary tasks / 107 turns with
the five app tools, plus 19 exploratory tool-profile cases / 27 turns. Workers use only synthetic
Vault and memory fixtures. There is no TTS, recording or access to the user's stored conversations.

The benchmark resumes in bounded 600-second batches. A started case may finish within its own
deadline; failed receipts are never rescheduled into passes. Turn, case and startup deadlines remain
60, 180 and 90 seconds. Timing includes model loading and reused runtimes, context work and tool
continuations. First text may be a preamble rather than an answer. Error turns remain in quality
scores but are excluded from completed-turn latency quantiles; they are listed separately.

All primary turns have evidence-bound full-rubric reviews by the implementing agent, not an
independent or blinded human. Strict name/number-only requests count. Reviews inspect actual
writes, sources and calls; an assurance to remember without persistence fails. They do not certify
every stylistic choice or incidental unrequested claim. For example, a correct direct Everest
answer passes its identity/routing task while its review flags an outdated incidental height.
The benchmark has already been used for diagnosis; its `heldout` case names now denote regression
cases, not an untouched independent holdout. One pass does not establish statistical improvement.

- [Complete rerun evidence and reviews](data/lfm-chat-rerun-2026-11-02.json.gz)
- [Derived measurements](data/lfm-chat-measurements-2026-11-02.json)
- [Diagnostic controls and failure investigations](data/lfm-chat-investigations-2026-11-02.json)
- [Content-free generation stage journal](data/lfm-chat-generation-stages-2026-11-02.json.gz)
- [Initial integration controls, including failures](data/lfm-integration-controls-2026-11-02.json.gz)
- [Separate summary-allowance replays](data/lfm-summary-controls-2026-11-02.json.gz)
- [Benchmark guide and bounded inference commands](../../Benchmarks/Chat/README.md)

Reproduce the published measurements without running inference:

```sh
python3 -B Benchmarks/Chat/benchmark.py audit \
  --archive docs/reports/data/lfm-chat-rerun-2026-11-02.json.gz \
  --output /tmp/sillies-lfm-audit
python3 -B scripts/summarize-chat-benchmarks.py \
  docs/reports/data/lfm-chat-rerun-2026-11-02.json.gz \
  --output /tmp/sillies-lfm-measurements.json
cmp docs/reports/data/lfm-chat-measurements-2026-11-02.json /tmp/sillies-lfm-measurements.json
```

The archive freezes the corpus, model revisions, runtime resources, binary hashes and review
evidence. Its audit reproduces stored checks and confirms evidence consistency; it is not an
independent semantic review or proof that another machine will generate identical replies.

Validation before publication: `make check BUILD_DIR=/tmp/sillies-lfm-final-check` passed, including
headless tests, architecture/format checks, fixture validation, native helper self-tests and helper
exit checks. All three evidence archives passed their audits. Regenerating the primary measurements
from the published archive produced a byte-for-byte match. The running app was not restarted.
