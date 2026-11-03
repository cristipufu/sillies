# Local Chat loop experiments — November 2–3, 2026

**Completed: 672 case runs and 1,048 planned turn receipts across eight models.** Every turn receipt received a full-rubric review, including failures and unexecuted follow-ups after a terminated case. Ten evidence archives reproduce their recorded checks and metrics. Nothing was pushed, committed, installed or restarted. Application source and the production catalog remain at the baseline; candidate patches are retained as experimental evidence.

The useful directions are larger prompt batches for Gemma 26B, fewer redundant summaries for LFM, and clearer retrieval contracts for Nemotron. **No tested configuration is a safe global improvement.** Prompt changes produced cross-model regressions, including forbidden memory writes in Apple’s isolated synthetic tests. These focused results do not replace the published 74-task scores.

## Speed: the three highest-scoring models

The same seven tasks were repeated twice: 14 whole-conversation tasks and 22 turns per row. Times are seconds per completed turn; errors remain in the task denominator. First text can be a preamble. P95 is included because a better median alone does not establish smoother interaction.

| Model | Runtime variant | Reviewed tasks | First text p50 | First text p95 | Completion p50 | Error entries |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Gemma 4 26B A4B | 64-token baseline | 14/14 | 11.18 | 25.15 | 11.23 | 0 |
| Gemma 4 26B A4B | SDK default prefill | 14/14 | 8.70 | 25.73 | 8.75 | 0 |
| Gemma 4 26B A4B | Bounded prefill + final-token tail | 14/14 | 6.87 | 27.28 | 6.94 | 0 |
| LFM2.5 24B A2B | 64-token baseline | 13/14 | 20.50 | 49.97 | 20.55 | 1 |
| LFM2.5 24B A2B | SDK default prefill | 11/14 | 15.30 | 34.78 | 16.23 | 4 |
| LFM2.5 24B A2B | Bounded prefill + final-token tail | 10/14 | 15.90 | 32.42 | 15.92 | 4 |
| Gemma 4 12B | 64-token baseline | 12/14 | 15.46 | 32.87 | 15.91 | 4 |
| Gemma 4 12B | SDK default prefill | 13/14 | 17.53 | 35.56 | 17.61 | 3 |
| Gemma 4 12B | Bounded prefill + final-token tail | 13/14 | 17.30 | 36.59 | 17.93 | 3 |

Gemma 26B’s best observed median improved from **11.18 to 6.87 seconds**, with 14/14 tasks passing both times. For identical first native requests, median prompt-processing speedup was 1.60× with SDK defaults and 1.93× with the final-token-tail variant. This supports investigating the forced 64-token batching overhead. It does not prove the tail adjustment alone accounts for the difference between the two candidates: their long-prompt paths are equivalent, and run conditions varied.

The slow end did not improve: the tail run contained a 21.88-second summary generation, including 10.75 seconds of prompt processing and 11.07 seconds of decoding. Those metrics locate the delay; they do not identify whether kernel preparation, system scheduling or another native-runtime cost caused it. No hardware-specific workaround was added.

LFM’s faster completed-turn medians came with more failures, so neither batching trial is an accepted improvement. Gemma 12B showed no end-to-end speed win. Its native output-limit failures remain visible; batching does not solve them. Missing native metrics from killed requests are not treated as zero time.

## Larger context: a separate diagnostic

This trial changes the frozen catalog’s working context from 4,096 to 8,192 tokens for the three large models. It uses the three long-history tasks, twice each. The baseline below is the matching subset of the seven-task baseline, not a fresh identically ordered run; initial model-loading positions therefore differ. Treat timing as exploratory.

| Model | Baseline tasks | 8K tasks | Baseline first text p50 | 8K first text p50 | Baseline → 8K error entries |
| --- | ---: | ---: | ---: | ---: | ---: |
| Gemma 4 26B A4B | 6/6 | 6/6 | 11.82 s | 9.85 s | 0 → 0 |
| LFM2.5 24B A2B | 5/6 | 6/6 | 35.33 s | 19.62 s | 1 → 0 |
| Gemma 4 12B | 4/6 | 4/6 | 21.37 s | 18.51 s | 4 → 4 |

LFM improved from 5/6 to 6/6 completed tasks. In comparable completed baseline first turns, initial compaction took two summaries; at 8K it took one. In the original latency baseline, recorded native summary decoding consumed 225.64 seconds, compared with 54.41 seconds for conversational decoding. Reducing unnecessary summarization is therefore a more promising direction than optimizing only reply-token generation.

All 8K cases still exercised compaction: the app separately caps recent history at 24 turns. The original compaction and retained-history checks were kept. Increasing context did not remove Gemma 12B’s incomplete responses. Peak memory and performance on smaller Macs were not measured, so this is not approval to raise context globally.

## Quality: the five fastest published models

Each cell is reviewed whole-conversation tasks passed out of **26**: thirteen scenarios, two repeats. These scores belong only to this diagnostic subset. “—” means not tested.

| Model | Baseline | Reply/memory policy | Publisher sampling | Tool parameter contracts |
| --- | ---: | ---: | ---: | ---: |
| Qwen3.5 2B | 11/26 | 9/26 | — | 11/26 |
| Nemotron Bolt E4B | 22/26 | 22/26 | 22/26 | 24/26 |
| Gemma 4 E4B | 18/26 | 20/26 | 19/26 | 17/26 |
| Granite 4.2 3B | 19/26 | 16/26 | 19/26 | 18/26 |
| Apple Intelligence | 10/26 | 10/26 | — | 6/26 |

- **Nemotron:** the tool-contract trial improved 22/26 to 24/26. Both long-record failures became correct two-call search/read results. The change only clarifies that an unspecified material type should use all categories and that a record-read query describes the requested detail, not the already-selected title. Automatic saving of a newly stated name still failed.
- **Gemma E4B:** the policy trial improved 18/26 to 20/26, but it also changed both saved-URL tasks from successful lookups into unnecessary clarifications. The tool-contract-only trial declined to 17/26. This is a trade-off, not a general fix.
- **Qwen 2B and Granite 3B:** no net gain on this thirteen-task set. Correct-looking words did not excuse false scientific explanations, invented access requirements or false confirmations of saved memories.
- **Apple:** no net policy gain. The contract trial declined to 6/26 and actually saved the fictional temporary password in both explicit no-store cases. Its opted-out preference writes were attempted but rejected because their references were malformed. Reject this as a shared default regardless of retrieval improvements elsewhere.

Publisher sampling did not produce a convincing general improvement. It left Nemotron and Granite level, and improved Gemma E4B by one task while trading other outcomes. No tested variant solved the new-name-saving probe across these models.

For completeness, these are completed-turn median **first text / completion** times; failure counts and all native stages are in the measurements archive. They must not be read as reliable speedups when task quality declines.

| Model | Baseline | Policy | Sampling | Tool contracts |
| --- | ---: | ---: | ---: | ---: |
| Qwen3.5 2B | 0.92 / 1.18 s | 0.92 / 1.27 s | — | 0.85 / 1.03 s |
| Nemotron Bolt E4B | 1.75 / 2.13 s | 1.58 / 2.54 s | 1.99 / 2.34 s | 1.34 / 1.80 s |
| Gemma 4 E4B | 1.31 / 1.71 s | 1.41 / 1.78 s | 1.60 / 2.01 s | 1.25 / 1.59 s |
| Granite 4.2 3B | 1.80 / 2.42 s | 2.06 / 2.81 s | 2.20 / 2.60 s | 1.71 / 2.40 s |
| Apple Intelligence | 2.48 / 2.54 s | 2.28 / 2.35 s | — | 2.44 / 2.49 s |

## Summary attribution: fresh matched comparisons

This follow-up compares baseline versus subject-oriented summary instructions on the same three history tasks, with two repeats and a fresh baseline for every model. The reply policy, tools, working capacity and generation allowances stay unchanged.

| Model | Baseline tasks | Revised summary tasks | First text p50, baseline → revised | Total summary calls, baseline → revised |
| --- | ---: | ---: | ---: | ---: |
| Qwen3.5 2B | 2/6 | 4/6 | 3.19 → 4.44 s | 14 → 18 |
| Nemotron Bolt E4B | 6/6 | 6/6 | 5.31 → 5.04 s | 10 → 10 |
| Gemma 4 E4B | 6/6 | 6/6 | 5.47 → 4.95 s | 10 → 10 |
| Granite 4.2 3B | 6/6 | 0/6 | 15.77 → 9.96 s | 28 → 23 |
| Apple Intelligence | 6/6 | 4/6 | 3.47 → 4.89 s | 10 → 22 |

Qwen’s incremental-history conversations improved in both repeats. Its standalone ownership question still failed: the new summary placed Mina under a release-code heading instead of preserving the checklist relationship clearly. This improved part of continuity without solving factual memory representation.

Granite’s revised summaries could retain the correct fact while the reply refused to use it. Its lower median therefore reflects faster failed tasks, not an improvement. Apple retained the requested facts but broke the exact-answer format, and the corrected-code follow-up required **seven summary calls in each repeat**, violating the unchanged incremental-compaction requirement. The revised summary policy is not suitable as a global replacement.

## App-side findings and next engineering work

1. **Reserve space for the replacement summary before choosing retained history.** [ConversationContextManager](../../Sources/SilliesReasoning/ConversationContextManager.swift) selects a suffix using the current memory, then generates a replacement and measures again. A growing replacement can consume the space just freed. In Apple’s seven-call turn, repeated measured reply inputs stayed at 2,503 tokens, above the 2,491-token target after reserving reply tokens; several further passes produced no net reduction. The seven summaries cost 18.82 seconds in one repeat. Budgeting prospective summary space is a concrete next experiment; its benefit has not yet been measured.
2. **Improve passage selection when a query repeats a known title.** [VaultRecordPassage](../../Sources/SilliesVault/VaultRecordPassage.swift) weights distinct matching query terms equally. An observed Granite query contained three title words and two detail words. The beginning scored three while the answer passage scored two, so the tool returned the wrong passage. Coverage and continuation metadata were present; the model also incorrectly generalized that partial excerpt to the whole record. [The reproduced window scores](data/chat-loop-2026-11-02/passage-analysis.json) separate this retrieval weakness from the model’s evidence interpretation. A generic ranker should account for record identity already being resolved; no case-specific ranking patch was added.
3. **Keep memory decisions separate from fluent acknowledgments.** New-name omissions, conflicting name keys, forbidden save attempts and false saved confirmations are observable execution/state failures. More confident prose is not progress. Test any change against actual persisted values and opt-outs, not only answer text.
4. **Pursue batching and exact-prefix cache reuse as runtime work.** Batching has measured promise for Gemma 26B. MLX requests still report zero cached prompt tokens. Persistent reuse was not tested; it needs an exact token ledger, invalidation on compaction/tool changes, bounded memory and correct treatment of recurrent/non-trimmable caches. Do not assume every model supports trimming the same cache implementation.

Apple’s screenshot failure was also traced: retrieval succeeded, then the response invented a base64 image; the existing app repetition check rejected it. Correct card/source data reached the conversation. General-question tool overuse and remaining generation failures are unresolved integration behavior, not proof of intrinsic model incapability. Gemma 12B’s native output-limit failures retain their stop reason and metrics; prior template/stop investigations remain in the [integration audit](chat-integration-audit-2026-11-02.md).

No global prompt, sampling or context default is changed from these results. Retained candidates use shared interfaces and native runtime options, with no case names, answer filters, model-ID conditionals or added dependencies in application logic. Before promoting a candidate, validate it on the full regression corpus and independent paraphrases, keeping speed, correctness and memory behavior separate.

## What was compared

The latency group is the three highest reviewed scores in the existing guide: Gemma 4 26B A4B,
LFM2.5 24B A2B and Gemma 4 12B. The quality group is the five lowest published median first-text
times: Qwen3.5 2B, Nemotron Bolt E4B, Gemma 4 E4B, Granite 4.2 3B and Apple Intelligence.

These are focused diagnostic comparisons, not a replacement for the 74-task leaderboard.
The latency corpus has seven tasks / eleven turns; the quality corpus has thirteen tasks /
twenty turns. Every variant repeats its corpus twice. Fixtures and expectations are copied
unchanged from the existing regression corpus, with the five-tool app profile only.

| Variant | Change | Held constant |
| --- | --- | --- |
| Baseline | Current committed implementation | Pinned model weights and native runtime |
| SDK prefill | Remove the app's forced 64-token batch size | Prompts, context, tool budget and sampling |
| Tail prefill | Bounded prompt chunks, reserving the final position for token selection even on short prompts | Baseline worker and all generation allowances |
| Policy | Clarify memory writes, corrections, conversation evidence and when tools are needed | Native helper, sampling, context and tool budget |
| Publisher sampling | Model-card sampling for Gemma E4B, Nemotron and Granite 3B | Baseline policy and native helper |
| Tool contract | Clarify category selection and distinguish record identity from passage keywords in two parameter descriptions | Baseline policy, helper, retrieval implementation and allowances |
| Compaction policy | Group summary facts by subject/topic and preserve attribution | Baseline reply policy, helper, tools, summary allowance and context capacity |
| 8K context diagnostic | Increase working context from 4,096 to 8,192 tokens on the three large models | Baseline policy, helper and output allowances |

The 8K diagnostic uses only the three long-history tasks. Its original compaction checks
remain in the evidence. Fitting a history without summarizing it can improve its response time,
but cannot pass as evidence of correct compaction or indefinite continuity.

## Research behind the experiments

The app forced 64-token prompt batches. The pinned MLX implementation uses 512 by default on
its generic LLM path and supports bounded balanced chunking. Its short-prompt path sends the
whole prompt into the first token-selection forward; the chunked path reserves a final token.
That distinction motivated a separate short-prompt experiment after the SDK-default trial
showed summary regressions. See the pinned [LLM preparation implementation](https://github.com/ml-explore/mlx-swift-lm/blob/3b339ad6e3b3f44c8121ecff5131c7fd55e075e6/Libraries/MLXLLM/LLMModel.swift)
and [prefill configuration](https://github.com/ml-explore/mlx-swift-lm/blob/3b339ad6e3b3f44c8121ecff5131c7fd55e075e6/Libraries/MLXLMCommon/PrefillParameters.swift).

The sampling experiments use temperature 1 and top-p 0.95. Gemma additionally uses top-k 64;
the other two leave top-k unrestricted. The trial disables the app's generic repetition penalty.
These settings follow [Gemma's guidance](https://gemma.ai/get-started/best-practices/),
[NVIDIA's model card](https://huggingface.co/nvidia/NVIDIA-Nemotron-3.5-Bolt-E4B-4GB), and
[IBM's model card](https://huggingface.co/ibm-granite/granite-4.2-3b). They retain Sillies' bounded
response allowance and reasoning mode; they are not reproductions of the publishers' benchmarks.
Catalog sampling applies to summaries as well as replies, so this trial also replaces the baseline's
greedy summary generation. It does not isolate changing conversation temperature alone.

[Qwen's recommendation](https://huggingface.co/Qwen/Qwen3.5-2B) also includes presence penalty,
which the existing catalog capability does not expose. The SDK has a presence-penalty processor,
but its prompt inclusion and bounded penalty context need review before claiming equivalent
publisher semantics. An incomplete preset was not tested or labeled an exact configuration.
Apple keeps its existing greedy native tool path and framework-owned session continuation;
see Apple's guidance on [session caching](https://developer.apple.com/documentation/foundationmodels/optimizing-key-value-caching-in-language-model-sessions)
and [context management](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window).

[Liquid's model card](https://huggingface.co/LiquidAI/LFM2.5-24B-A2B) documents a reasoning model
with more context capacity than the app's 4K working limit. The experiment preserves its native
reasoning and output allowance; it does not insert a fake closing reasoning delimiter to force
an answer. Neither the Nemotron conversational template mode nor persistent MLX prompt-cache
reuse was tested here.

The tool-contract follow-up was declared after the first runs repeatedly searched only one
wrong category. It uses the same thirteen tasks and two repeats for all five fast models. It
adds no retries, query rewriting, answer filters or case-specific conditions. Because it was
motivated by failures already observed here, it is a diagnostic follow-up, not independent
validation of the new descriptions.

A final compaction follow-up compares the existing and revised summary instructions on the
three long-history scenarios, twice each, for all five fast models. It was motivated by observed
summary corruption and lost attribution. Each model has a fresh matched baseline, with variant
order alternated between models. It is separate from the thirteen-task quality comparison.

## Measurement and review limits

- One M4 Pro with 48 GiB RAM, macOS 26.7.2, release binaries, one native inference process at a time.
  Compilation was paused during timed inference. No TTS, visible windows or private user records.
- Binary/resource hashes, model revisions, source patches, corpus hashes, raw receipts and failures
  are retained. Sampling and context experiments change frozen worker catalog resources, not the
  production catalog. The committed baseline is `1070a01`; experimental binaries include the
  separately retained uncommitted patches.
- Two repeats, order seed 271828, 60-second turn, 180-second case and 90-second startup deadlines.
  The seed controls case ordering, not native sampling. Native sampling remains stochastic.
- Batches are bounded to 600 seconds; an already started case can finish within its own deadline.
  Failed receipts are not retried into passes. Later unexecuted turns in a killed case remain failed
  entries rather than being misrepresented as independently observed native faults.
- First text can be a preamble, not a substantive answer or the start of speech. Completed-turn
  medians exclude errors, so completion failures are reported beside them. Initial model loading
  and reused runtimes are mixed. No claim is made about peak memory on smaller Macs.
- Percentiles use the benchmark's nearest-observation convention, including p50 for even sample
  counts. Model trials alternate some variant ordering but do not constitute a randomized hardware
  crossover; background system load and thermal state were not controlled. Identical-request native
  timing pairs help separate prompt processing from changed answers, but do not eliminate those limits.
- Full-rubric reviews inspect replies, executed tools, returned evidence and actual memory state.
  The reviewer is the implementing agent, not independent or blinded. Strict requested answer
  formats count. These previously exposed cases are regression probes, not an untouched holdout.
- Small repeated subsets can identify useful implementation problems. They do not establish
  statistical significance, broad model rankings or the best achievable performance of a model.

## Evidence and validation

The [combined measurements](data/chat-loop-2026-11-02/measurements.json) include per-repeat
outcomes, timing sample counts, exact-answer timing, native generation stages, actual memory
checks and identical-request prompt comparisons. The [manifest](data/chat-loop-2026-11-02/manifest.json)
records file hashes and completed/planned coverage.

| Evidence archive | Case receipts | Turn receipts |
| --- | ---: | ---: |
| [context-context](data/chat-loop-2026-11-02/context-context.json.gz) | 18/18 | 30 |
| [continuity-baseline](data/chat-loop-2026-11-02/continuity-baseline.json.gz) | 30/30 | 50 |
| [continuity-summary](data/chat-loop-2026-11-02/continuity-summary.json.gz) | 30/30 | 50 |
| [latency-baseline](data/chat-loop-2026-11-02/latency-baseline.json.gz) | 42/42 | 66 |
| [latency-prefill](data/chat-loop-2026-11-02/latency-prefill.json.gz) | 42/42 | 66 |
| [latency-tail-prefill](data/chat-loop-2026-11-02/latency-tail-prefill.json.gz) | 42/42 | 66 |
| [quality-baseline](data/chat-loop-2026-11-02/quality-baseline.json.gz) | 130/130 | 200 |
| [quality-policy](data/chat-loop-2026-11-02/quality-policy.json.gz) | 130/130 | 200 |
| [quality-sampling](data/chat-loop-2026-11-02/quality-sampling.json.gz) | 78/78 | 120 |
| [quality-tool-contract](data/chat-loop-2026-11-02/quality-tool-contract.json.gz) | 130/130 | 200 |

The [controls archive](data/chat-loop-2026-11-02/controls.json.gz) contains frozen plans, schedules,
source patches, actual sampling/context catalogs, build/run logs and the analysis script. Corpus
snapshots, model revisions, binary/resource hashes, raw model inputs/outputs, tool execution,
persisted state and review hashes are retained in the result archives. Native reasoning-channel
contents are not published. The [passage analysis](data/chat-loop-2026-11-02/passage-analysis.json)
and [compaction trace analysis](data/chat-loop-2026-11-02/compaction-analysis.json) inspect existing
receipts; neither is a newly scored intervention.

Validation completed after timed inference stopped: three native helper self-tests, four relevant
synthetic-fixture checks, strict Swift formatting of all five reconstructed source patches, and
all ten archive audits. See the [check results](data/chat-loop-2026-11-02/verification.json) and
[format results](data/chat-loop-2026-11-02/format-verification.json). Candidate release binaries
compiled successfully. No full `make check` or GUI suite was run for the final documentation-only
diff; these prototypes are not being shipped. All benchmark inference processes exited.

Reproduce an archive's checks and metrics without inference:

```sh
python3 -B Benchmarks/Chat/benchmark.py audit \
  --archive docs/reports/data/chat-loop-2026-11-02/quality-tool-contract.json.gz \
  --output /tmp/sillies-loop-audit

python3 -B scripts/summarize-chat-benchmarks.py \
  docs/reports/data/chat-loop-2026-11-02/quality-tool-contract.json.gz \
  --output /tmp/sillies-loop-measurements.json
```

Archive integrity is not independent semantic review or a quality certification. The combined
analysis source is retained under `files["analyze-experiments.py"]` in the controls archive; it
uses the repository's existing audited measurements and percentile convention.
