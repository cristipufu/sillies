# Local text models

Settings → **Local AI** offers Apple Intelligence plus twelve optional MLX models. Speech recognition stays in **Speech & Meetings** and has its own selection. Downloading never selects a model automatically. Selection applies to notes, Participate suggestions, Chat replies, dictation cleanup, and selection commands. The Vault's **Regenerate notes** action applies the selected model to an existing transcript without transcribing or recording again.

## Which model should I use?

Sillies requires an Apple silicon Mac with macOS 26 or later. The memory figures below are the
app's minimum admission requirements; all measured timings come from the same 48 GiB Mac.

**For Chat quality, Gemma 4 26B A4B is the strongest measured option if your Mac meets its 32 GB memory requirement.** Qwen3.5 4B is the smaller, quicker compromise at 16 GB. None passed every task, and the smaller models were especially unreliable at automatically saving memories.

| Model | Model release | Required Mac RAM | Download | Reviewed task score | Median first text | Practical fit |
| --- | --- | --- | --- | --- | --- | --- |
| **Gemma 4 26B A4B** | [2026-04-02](https://blog.google/innovation-and-ai/technology/developers-tools/gemma-4/) | 32 GB | 15.37 GB | **94.6/100** (70/74) | 4.92 s | Highest task score; slower replies. Corrections can still leave conflicting memories. |
| Ministral 3 8B | [2025-12-02](https://mistral.ai/news/mistral-3) | 24 GB | 5.61 GB | **73.0/100** (54/74) | 3.98 s | Useful retrieval; unreliable memory writes. Small score gain over 4B. |
| Qwen3.5 9B | [2026-03-02](https://github.com/QwenLM/Qwen3.8#news) | 24 GB | 5.97 GB | **71.6/100** (53/74) | 4.07 s | Little observed gain over 4B, with slower replies. |
| **Qwen3.5 4B** | [2026-03-02](https://github.com/QwenLM/Qwen3.8#news) | 16 GB | 3.05 GB | **70.3/100** (52/74) | 2.22 s | Smaller, faster compromise; weak automatic memory saves. |
| Gemma 4 E4B | [2026-04-02](https://blog.google/innovation-and-ai/technology/developers-tools/gemma-4/) | 16 GB | 5.18 GB | **63.5/100** (47/74) | 1.16 s | Quicker chats; weaker tool follow-through and memory saves. |
| Qwen3.5 2B | [2026-03-02](https://github.com/QwenLM/Qwen3.8#news) | 8 GB | 1.74 GB | **40.5/100** (30/74) | 0.76 s | Smallest download and quickest first text; frequent task failures. |
| Apple Intelligence | System-managed | Apple-compatible Mac | System-managed | **23.0/100** (17/74) | 2.07 s | No separate Sillies download; poor fit for this Chat/Vault workflow. |

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
The 22 added scenarios also received two further passes to expose variability, scored automatically
and reported separately. See the [full results, failures, methodology and downloadable evidence](reports/local-chat-models-2026-11-02.md).

The helper derives its allocation budget from verified artifact sizes plus workspace, capped at 32 GiB and two thirds of physical memory. Oversized models fail admission before native loading. Gemma 26B activates a subset of its parameters per token, but its full quantized weights still need memory.

These are conservative admission limits for sharing the Mac with transcription and other apps, not measured peak-memory promises. Language coverage comes from the upstream model cards; actual summarization quality needs evaluation with representative recordings. Multilingual tokenizer/chat-template checks do not establish accuracy in every supported language. Apple Intelligence remains the default and retains its own hardware, availability and language requirements.

Models are pinned in `Sources/SilliesModelStore/Resources/text-models.json`, including weights, tokenizer, chat template, revision, lengths, SHA-256 hashes, license, and original release date with its source. They live in `~/Library/Application Support/Sillies/TextModels/<id>/<revision>`. Downloads use the same verified, resumable, atomic installer as speech models. Partial installations cannot be selected. No remote code, inference server, Python installation, or inference network call is involved. The existing daily speech-model update mechanism does not yet update text-model revisions; those pins ship with the app.

## New model evaluation

The catalog also includes Nemotron 3.5 Bolt E4B, Gemma 4 12B, Granite 4.2 3B and 8B,
and LFM2.5 2.6B and 24B A2B. Their integration and evaluation are in progress; the scores above
remain the earlier seven-model comparison until the new runs have been reviewed. The
[app-first failure investigation](reports/chat-integration-audit-2026-11-02.md) found and corrected
context admission, tool-limit completion, record-passage selection and memory-replacement defects.
A fresh thirteen-model comparison is underway using the corrected implementation. Its results
will replace the table after review; historical and corrected runs are kept separate.

Ling 3.0 Tiny (`bailing_hybrid`) and Bonsai 2 (`prism_hadamard_qwen35`) remain candidates.
The pinned native Swift runtime does not implement their architectures. Their downloadable
MLX weights alone do not make them usable in Sillies; they are not offered as working downloads.

## Benchmarks

- **[Reviewed seven-model comparison and raw results](reports/local-chat-models-2026-11-02.md)** —
  scores by task group, memory writes, repeat variability, compaction and release-build latency.
- **[Benchmark guide](../Benchmarks/Chat/README.md)** — cases, scoring, bounded runs and reproducibility.
- **[Benchmark audit and corrections](reports/chat-benchmark-audit-2026-11-02.md)** — what the evidence
  supports, false passes, corrected context cases and remaining validation gaps.
- **[Original exploratory comparison](reports/local-chat-models-2026-11-01.md)** — preserved historical results.

The original audit found false passes in open-ended cases and context fixtures that left the target
fact in recent messages. The current comparison uses corrected context fixtures, actual persisted
state, full primary-turn rubric reviews and separate repeated checks. Independent tasks, human review
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

One downloaded text model is loaded at a time. Each request starts a fresh prompt cache. Chat reconstructs native conversation messages from its bounded working context; meeting tasks remain independent. Input is checked against a 4,096-token total context. Tasks request at most 1,400 generation tokens (Chat normally requests 240). LFM2.5 always reasons, so its catalog policy grants an additional 1,024 total generation tokens. Context measurement and compaction reserve that allowance too. This is a bounded total allowance, not a guaranteed split between reasoning and answer tokens; an unfinished response still fails rather than exposing private reasoning. MLX uses the model-specific allocation budget described above, with a 128 MiB cache. These limits do not describe total process RSS or all driver allocations.

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
