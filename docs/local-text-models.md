# Local text models

Settings → **Local AI** offers Apple Intelligence plus twelve optional MLX models. Speech recognition stays in **Speech & Meetings** and has its own selection. Downloading never selects a model automatically. Selection applies to notes, Participate suggestions, Chat replies, dictation cleanup, and selection commands. The Vault's **Regenerate notes** action applies the selected model to an existing transcript without transcribing or recording again.

## Which model should I use?

Sillies requires an Apple silicon Mac with macOS 26 or later. The memory figures below are the
app's minimum admission requirements; all measured timings come from the same 48 GiB Mac.

**Gemma 4 26B A4B has the strongest Chat task score in this comparison and requires 32 GB RAM.**
For a 24 GB Mac, Nemotron Bolt offers a promising balance of responsiveness and task completion;
Gemma 12B scores higher but responds more slowly. At 16 GB, Granite 8B scores higher than Qwen 4B,
while Qwen starts responding sooner on the test Mac. LFM 2.6B has the strongest listed score among
models admitted on an 8 GB Mac, but its new median first text is 6.46 seconds and long-history
continuity remains uneven. These are integration results, not measurements on each RAM
configuration. Automatic memory saving remains unreliable across several models.

For continuing conversations, also read the [context, summary and identity follow-up](reports/continuity-review-2026-11-03.md).
It reproduces Apple's difficulty correcting an earlier mistaken identity, reviews source attribution,
and checks repeated checkpoint rollover separately from answer accuracy. Those controls do not replace
the scored comparison below.
The [archive-recall investigation](reports/archive-recall-2026-11-03.md) fixes missing passages in
conversation search and records the remaining tool-selection failures separately from retrieval.
The [memory-tool follow-up](reports/memory-tool-contracts-2026-11-03.md) records explicit write outcomes,
rejected prompt experiments and fresh-case results; automatic memory decisions remain imperfect.
The [channel and memory decision follow-up](reports/channel-memory-followup-2026-11-03.md) completes
the interrupted evaluation, fixes a Gemma streaming marker leak, and measures an Apple-only planning
experiment that was rejected. Additional inference strategies must earn their latency cost for each
model; no classifier has been enabled globally.
The [checkpoint-settings audit](reports/checkpoint-generation-settings-2026-11-03.md) identifies and
fixes Gemma 12B's missing token-suppression requirement, with exact native replays and a review of
all twelve downloadable text checkpoints. It does not replace the scored comparison below.
The [bounded automatic-memory experiments](reports/memory-improvement-2026-11-03.md) compare
supporting quotes and separate memory preparation for Gemma 12B and Apple. Neither strategy met
the acceptance criteria; no experimental strategy is enabled and the scores below are unchanged.
The [app-only strategy retry](reports/app-strategies-2026-11-03.md) tests separate save/correct tools,
bounded preloaded memories and native session-cache reuse. It includes model-specific outcomes
and integration failures; its diagnostic subsets do not change the leaderboard below.
The [native integration follow-up](reports/native-conversation-integration-2026-11-04.md) implements
Granite 8B's measured conversation-cache improvement and fixes Ministral's interrupted-message
formatting. It also completes Qwen 4B's frozen memory-policy validation; that policy remains disabled.
Its warm-follow-up timings are separate from the whole-task measurements in this table.

| Model | Model release | Required Mac RAM | Download | Reviewed task score | Median first text |
| --- | --- | --- | --- | --- | --- |
| Gemma 4 26B A4B | [2026-04-02](https://blog.google/innovation-and-ai/technology/developers-tools/gemma-4/) | 32 GB | 15.37 GB | **97.3/100** (72/74) | 5.41 s |
| LFM2.5 24B A2B | [2026-10-13](https://www.liquid.ai/blog/lfm2-5-24b-a2b) | 32 GB | 13.59 GB | **85.1/100** (63/74) | 9.41 s |
| Gemma 4 12B | [2026-06-03](https://blog.google/innovation-and-ai/technology/developers-tools/introducing-gemma-4-12b/) | 24 GB | 6.77 GB | **83.8/100** (62/74) | 6.22 s |
| LFM2.5 2.6B | [2026-08-04](https://www.liquid.ai/blog/lfm2-5-2-6b) | 8 GB | 1.60 GB | **82.4/100** (61/74) | 6.46 s |
| Nemotron 3.5 Bolt E4B | [2026-10-23](https://research.nvidia.com/labs/nemotron/NVIDIA-Nemotron-3.5-Bolt-E4B-4GB/) | 24 GB | 7.52 GB | **78.4/100** (58/74) | 1.27 s |
| Granite 4.2 8B | [2026-08-25](https://research.ibm.com/blog/introducing-granite-4-2) | 16 GB | 4.95 GB | **74.3/100** (55/74) | 4.86 s |
| Ministral 3 8B | [2025-12-02](https://mistral.ai/news/mistral-3) | 24 GB | 5.61 GB | **71.6/100** (53/74) | 4.49 s |
| Qwen3.5 9B | [2026-03-02](https://github.com/QwenLM/Qwen3.8#news) | 24 GB | 5.97 GB | **70.3/100** (52/74) | 5.36 s |
| Gemma 4 E4B | [2026-04-02](https://blog.google/innovation-and-ai/technology/developers-tools/gemma-4/) | 16 GB | 5.18 GB | **66.2/100** (49/74) | 1.38 s |
| Qwen3.5 4B | [2026-03-02](https://github.com/QwenLM/Qwen3.8#news) | 16 GB | 3.05 GB | **63.5/100** (47/74) | 2.37 s |
| Granite 4.2 3B | [2026-08-25](https://research.ibm.com/blog/introducing-granite-4-2) | 8 GB | 2.07 GB | **55.4/100** (41/74) | 2.00 s |
| Qwen3.5 2B | [2026-03-02](https://github.com/QwenLM/Qwen3.8#news) | 8 GB | 1.74 GB | **39.2/100** (29/74) | 0.98 s |
| Apple Intelligence | System-managed | Apple-compatible Mac | System-managed | **24.3/100** (18/74) | 2.28 s |

Rows are ordered by reviewed task score, highest first. **The two LFM rows use the newer integration
rerun; the other eleven retain the earlier comparison.** These are the latest measured results,
not a uniform comparison of every model on the same app build.
See the [LFM fixes, before/after results and remaining failures](reports/lfm-chat-rerun-2026-11-02.md).

Model release is the original publisher’s release date, not the MLX conversion upload date. Apple’s current model asset release date is not exposed by the system.

**Score:** reviewed tasks passed out of 74, expressed on a 100-point scale. Each task includes
its whole conversation: general answers, Vault retrieval, identity, memories, topic changes or
context compaction. A fluent reply that invents a source or fails to save a requested memory does
not pass. Strict formatting requests also count. This is a Sillies task score, not a percentage of
all world knowledge the model knows.

**Timing:** median first streamed text on one M4 Pro with 48 GiB, using release builds. That text
can be a preamble; it is not necessarily the answer or the start of speech. Initial loads and reused
runtimes are mixed. These timings do not predict performance on every Mac with the listed RAM.

All 107 primary turns per model were reviewed by the implementing agent, not an independent human.
Each published build has one full pass; earlier repeated checks do not establish repeatability for
these scores. The LFM rerun uses the unchanged corpus after integration fixes and retains all failed
cases. See the [original thirteen-model results and evidence](reports/corrected-local-chat-models-2026-11-02.md)
and the [new LFM results and evidence](reports/lfm-chat-rerun-2026-11-02.md).

The helper derives its allocation budget from verified artifact sizes plus workspace, capped at 32 GiB and two thirds of physical memory. Oversized models fail admission before native loading. Gemma 26B activates a subset of its parameters per token, but its full quantized weights still need memory.

These are conservative admission limits for sharing the Mac with transcription and other apps, not measured peak-memory promises. Language coverage comes from the upstream model cards; actual summarization quality needs evaluation with representative recordings. Multilingual tokenizer/chat-template checks do not establish accuracy in every supported language. Apple Intelligence remains the default and retains its own hardware, availability and language requirements.

Models are pinned in `Sources/SilliesModelStore/Resources/text-models.json`, including weights, tokenizer, chat template, revision, lengths, SHA-256 hashes, license, and original release date with its source. They live in `~/Library/Application Support/Sillies/TextModels/<id>/<revision>`. Downloads use the same verified, resumable, atomic installer as speech models. Partial installations cannot be selected. No remote code, inference server, Python installation, or inference network call is involved. The existing daily speech-model update mechanism does not yet update text-model revisions; those pins ship with the app.

## Catalog coverage

The comparison includes all twelve downloadable models plus Apple Intelligence. Before this run,
the [app-first investigation](reports/chat-integration-audit-2026-11-02.md) corrected context admission,
tool-limit completion, record-passage selection and memory replacement. Remaining failures include
application-side summary fallback loss and model/prompt difficulties with memory decisions and
retrieval. The subsequent LFM integration adds stream-boundary validation, recoverable argument
errors, publisher sampling and capacity-based compaction; both LFMs were then fully rerun. Long
histories and evidence interpretation still fail in some cases. Verified causes remain separate
from unresolved ones, and no model is assumed intrinsically incapable based on an app failure.
Historical results are preserved separately; no failing case was silently retried into a pass.

Ling 3.0 Tiny (`bailing_hybrid`) and Bonsai 2 (`prism_hadamard_qwen35`) remain candidates.
The pinned native Swift runtime does not implement their architectures. Their downloadable
MLX weights alone do not make them usable in Sillies; they are not offered as working downloads.

## Benchmarks

- **[Stored Chat: one million messages and restart recovery](reports/stored-conversation-scale-2026-11-03.md)** —
  growing SQLite histories, browsing and selection during streaming, common-term search performance,
  and recovery after killing a writer. These application checks use fake inference, not model scores.
- **[Long-lived conversations: bounded replies and background checkpoints](reports/long-lived-chat-2026-11-03.md)** —
  synthetic scale, durable checkpoints, real-model interruption and archive-recall controls.
  These focused measurements do not replace the full-corpus leaderboard above.
- **[Per-model profiles and agent-loop engineering](reports/agent-profiles-2026-11-03.md)** —
  fresh baseline/candidate comparisons, context-capacity experiments and remaining failures.
  These focused results do not replace the full-corpus scores above. See the
  [profile and budget contracts](model-profiles.md) for contributor guidance.
- **[Chat loop experiments: speed, retrieval and compaction](reports/chat-loop-experiments-2026-11-02.md)** —
  controlled diagnostic comparisons with gains, regressions and raw evidence; these subset results
  do not replace the leaderboard above or change the app's defaults.
- **[LFM integration fixes and full rerun](reports/lfm-chat-rerun-2026-11-02.md)** —
  updated scores for both LFMs, diagnostic controls, latency trade-offs and remaining failures.
- **[Reviewed thirteen-model comparison and raw results](reports/corrected-local-chat-models-2026-11-02.md)** —
  scores by task group, memory writes, compaction, release-build latency and app-first investigations.
- **[Historical seven-model comparison](reports/local-chat-models-2026-11-02.md)** —
  earlier integration results and its separate repeated checks.
- **[Benchmark guide](../Benchmarks/Chat/README.md)** — cases, scoring, bounded runs and reproducibility.
- **[Benchmark audit and corrections](reports/chat-benchmark-audit-2026-11-02.md)** — what the evidence
  supports, false passes, corrected context cases and remaining validation gaps.
- **[Original exploratory comparison](reports/local-chat-models-2026-11-01.md)** — preserved historical results.

The original audit found false passes in open-ended cases and context fixtures that left the target
fact in recent messages. The current comparison uses corrected context fixtures, actual persisted
state and full primary-turn rubric reviews. Independent tasks, repeated runs, human review
and additional physical Macs are still needed for broad release claims. Chat scores do not establish
meeting-summary, dictation-cleanup or TTS quality, and no model default changes from these results alone.

## Ownership and extension points

| Concern | Owner |
| --- | --- |
| Model metadata | `SilliesCore.TextModelDescriptor` |
| Catalog, verified downloads, disk space and installation leases | `SilliesModelStore` |
| Runtime contracts and one loaded model | `SilliesTextModels.TextModelProvider`, `PreparedTextModel`, `TextModelRegistry` |
| CPU/GPU work priority | `SilliesInference.InferenceActivity` |
| Native MLX inference, tokenizer adaptation, context and output limits | `SilliesTextInference` helper |
| App-owned backend selection and lifetime | `App/Composition/ReasoningServices`, `TextModelEnvironment` |
| Task prompts, languages, source evidence and protected-content checks | `SilliesReasoning`: `LocalReasoning`, `LocalReasoningService`, `ReasoningBackend`, `LocalTextTransform` |
| Download presentation and Settings actions | `TextModelsPresentation`, `TextModelSettingsView` |

Adding another compatible MLX model:

1. Add its pinned repository/revision and display/hardware metadata to `scripts/update-text-catalog.py`. Run the generator. Review the resulting manifest, license, chat template, required artifacts, architecture support in the pinned MLX runtime, and total disk size. Models do not require new UI branches.
2. Run catalog validation and the helper's tokenizer check on the pinned local support files. The Swift tokenizer must load entirely from the installed folder. Models requiring custom tokenizer code need an adapter rather than a catalog-only change.
3. Use the bounded benchmark below with supported languages, mixed-language text, names, dates and identifiers. Check malformed/incomplete output, cancellation and speech contention. Do not advertise a language solely because the tokenizer can encode it.
4. Update the catalog regression expectations and attribution. Keep IDs stable; never replace a pinned revision silently in an existing installation.

Adding a different text runtime:

1. Implement `TextModelProvider.prepare` and `PreparedTextModel.generate/stop`, returning plain text through `TextGenerationRequest`. Register the provider once in `App/Composition/ReasoningServices`; the catalog supplies its `providerID`.
2. Keep heavyweight SDK imports and native inference in a separate helper target. The architecture checker rejects MLX/tokenizer SDK imports in the app. Use bounded IPC with an execution deadline, cancellation, crash recovery, and explicit teardown. Do not move inference into a view or the meeting controller.
3. Reuse `ModelArtifactManifest`/`ModelStore` and `TextModelRegistry`; do not create another downloader, selection flow, or cache. Add the helper/resources/licenses to `scripts/build-app.sh`.
4. Satisfy the same provider contract tests. A compatible text model needs no changes to capture, transcript rendering, mascot behavior, or window tracking.

For a new STT engine, follow [the separate speech-provider recipe](local-speech-models.md#extending-providers-and-models). Speech streams PCM and incremental timestamped phrases; text models consume bounded text and return one result. They share artifact storage and resource priority without pretending these are the same inference contract.

## Resource and failure behavior

One downloaded text model is loaded at a time. Each request starts a fresh prompt cache. Chat reconstructs native conversation messages from its bounded working context; meeting tasks remain independent. Input is checked against a 4,096-token total context. Tasks request at most 1,400 generation tokens (Chat normally requests 240). LFM2.5 always reasons, so its catalog policy grants 1,024 additional generation tokens for replies and ordinary transformations, or 2,048 for history summaries. Context measurement and source splitting reserve the same allowance. This is a bounded combined ceiling, not a guaranteed split between reasoning and answer tokens; unfinished responses fail. Native reasoning channels are separated from visible text. Orphaned closing delimiters are now rejected before that delimiter reaches the streaming sink, including split chunks; this does not validate arbitrary generated prose. The [LFM rerun](reports/lfm-chat-rerun-2026-11-02.md) documents the verified boundary fix and remaining generation failures. MLX uses the model-specific allocation budget described above, with a 128 MiB cache. These limits do not describe total process RSS or all driver allocations.

The helper runs at utility priority. Speech inference preempts active downloaded-text inference, waits for worker exit, and allows interrupted text work to retry once speech is idle. Explicit dictation reserves that priority through finalization, including Apple Speech. Text model leases prevent deletion while loading or generating. A 60-second idle release, pause/exclusion handling, selection changes, and termination release the worker. IPC responses are bounded to 128 KiB and each request has a 120-second deadline. The app does not wait synchronously for helper exit.

Interactive writing goes ahead of queued background notes, and long meetings yield between chunks. Dictation retains its separate 750 ms cleanup deadline: if loading or generation misses it, the finalized transcript is inserted once. A delayed model output never rewrites the destination. This means larger models may improve meeting notes without being fast enough for dictation cleanup.

Generated notes must decode to the expected schema. Truncated output and unexpected reasoning/tool output are rejected for text-only tasks. Chat handles native tool calls through explicitly injected local capabilities. Task commitments must match source passages before translation. Writing retains the existing name/number/identifier guards. Failures preserve source material and label extracted highlights honestly. Capture warnings and notes-generation notices have separate saved fields.

## Chat context and tools

Chat keeps the full conversation visible while incrementally summarizing older turns for the model.
Recent turns, native tool results, and actual record references preserve continuity within the selected
model's context limit. Compaction is lossy and scoped to the active chat. Read-only Vault tools can
retrieve saved screenshots, URLs, and meeting passages; result cards open actual records. Screenshot
retrieval uses OCR and metadata, not pixel understanding. See [the Chat tool guide](contributing/chat-tools.md)
for budgets, recovery behavior, and provider requirements.

Native tool APIs are provided by [Apple Foundation Models](https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling)
and [MLX Swift LM](https://github.com/ml-explore/mlx-swift-lm/blob/main/skills/mlx-swift-lm/references/tool-calling.md).
A model must have a supported tool format in the pinned runtime; family support alone does not establish
reliable tool selection or answer quality.

## Bounded verification

`make check` covers contracts, storage, cancellation, worker exits, queue behavior, JSON/evidence handling, offscreen interface layout, and a real Metal-kernel self-test of the bundled helper. `make stress` covers bounded audio/transcript workloads. Tests do not download model weights. To keep a running app untouched:

```sh
make check BUILD_DIR=/tmp/sillies-verification
```

Native development requires Xcode's Metal toolchain (`xcodebuild -downloadComponent MetalToolchain` if missing). Users get the compiled helper and Metal library in Sillies.app.

Optional real-model validation separates download time from bounded execution:

```sh
source scripts/toolchain.sh
swift build --product TextModelBenchmark
swift build --product SilliesTextInference
text_benchmark="$(swift build --show-bin-path)/TextModelBenchmark"
"$text_benchmark" install qwen-3.5-4b /tmp/sillies-text-models
python3 scripts/run-bounded-test.py 120 "$text_benchmark" run qwen-3.5-4b /tmp/sillies-text-models
```

Use another catalog ID, such as `qwen-3.5-2b`, `qwen-3.5-9b`, `gemma-4-e4b`, `gemma-4-26b-a4b`, or `ministral-3-8b`, to check another model. The benchmark loads the installed files offline through `DownloadedReasoningBackend`, including the same JSON shaping and fence handling used by the app. It checks three short monolingual and mixed-language outputs against required source facts, prints request-to-result timings, and shuts the runtime down. It is a smoke check, not an accuracy leaderboard or a guarantee of interactive latency on other Macs.

The helper also accepts `--check-tokenizer /path/to/pinned-local-files` for a small multilingual round-trip/chat-template check and `--self-test` for bundled GPU-kernel validation. Neither command downloads anything.

Model quality cases belong in `Tools/TextModelBenchmark/TextQualityFixtures.swift`, not in provider-specific production heuristics. The benchmark checks required facts and prints every output for semantic review. Runtime schema/evidence checks cannot guarantee that a generated summary is factually correct.

Earlier summarization smoke checks on an M4 Pro with 48 GB (debug build): all six pinned tokenizers/templates passed the multilingual round-trip check. Full-weight Qwen3.5 4B runs took roughly 12–23 seconds for the first request including hash verification/loading, then 1–1.4 seconds per short warm request. Qwen3.5 2B took about 3.6 seconds for the first request and 0.7–0.9 seconds for subsequent short requests. Both preserved the monolingual fixture facts but changed a weekday in the mixed-language fixture, which the quality check reports as a failure. No production weekday workaround is used. All six downloads subsequently received the full-weight **Chat** evaluation linked above. That comparison does not certify their meeting summaries, and these earlier timings are not a current cross-model comparison.
