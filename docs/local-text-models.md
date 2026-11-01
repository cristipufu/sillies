# Local text models

Settings → **Local AI** offers Apple Intelligence plus six optional MLX models. Speech recognition stays in **Speech & Meetings** and has its own selection. Downloading never selects a model automatically. Selection applies to notes, Participate suggestions, Chat replies, dictation cleanup, and selection commands. The Vault's **Regenerate notes** action applies the selected model to an existing transcript without transcribing or recording again.

| Model | Approximate download | Required unified memory |
| --- | --- | --- |
| Qwen3.5 2B, 4-bit | 1.74 GB | 8 GB |
| Qwen3.5 4B, 4-bit | 3.05 GB | 16 GB |
| Qwen3.5 9B, 4-bit | 5.97 GB | 24 GB |
| Gemma 4 E4B, 4-bit | 5.18 GB | 16 GB |
| Gemma 4 26B A4B, 4-bit | 15.37 GB | 32 GB |
| Ministral 3 8B Instruct, 4-bit | 5.61 GB | 24 GB |

The helper derives its allocation budget from verified artifact sizes plus workspace, capped at 32 GiB and two thirds of physical memory. Oversized models fail admission before native loading. Gemma 26B activates a subset of its parameters per token, but its full quantized weights still need memory.

These are conservative admission limits for sharing the Mac with transcription and other apps, not measured peak-memory promises. Language coverage comes from the upstream model cards; actual summarization quality needs evaluation with representative recordings. English and Romanian tokenizer/chat-template checks do not establish accuracy in every supported language. Apple Intelligence remains the default and retains its own hardware, availability and language requirements.

Models are pinned in `Sources/SilliesModelStore/Resources/text-models.json`, including weights, tokenizer, chat template, revision, lengths, and SHA-256 hashes. They live in `~/Library/Application Support/Sillies/TextModels/<id>/<revision>`. Downloads use the same verified, resumable, atomic installer as speech models. Partial installations cannot be selected. No remote code, inference server, Python installation, or inference network call is involved. The existing daily speech-model update mechanism does not yet update text-model revisions; those pins ship with the app.

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
3. Use the bounded benchmark below with English, Romanian, mixed-language text, names, dates and identifiers. Check malformed/incomplete output, cancellation and speech contention. Do not advertise a language solely because the tokenizer can encode it.
4. Update the catalog regression expectations and attribution. Keep IDs stable; never replace a pinned revision silently in an existing installation.

Adding a different text runtime:

1. Implement `TextModelProvider.prepare` and `PreparedTextModel.generate/stop`, returning plain text through `TextGenerationRequest`. Register the provider once in `App/Composition/ReasoningServices`; the catalog supplies its `providerID`.
2. Keep heavyweight SDK imports and native inference in a separate helper target. The architecture checker rejects MLX/tokenizer SDK imports in the app. Use bounded IPC with an execution deadline, cancellation, crash recovery, and explicit teardown. Do not move inference into a view or the meeting controller.
3. Reuse `ModelArtifactManifest`/`ModelStore` and `TextModelRegistry`; do not create another downloader, selection flow, or cache. Add the helper/resources/licenses to `scripts/build-app.sh`.
4. Satisfy the same provider contract tests. A compatible text model needs no changes to capture, transcript rendering, mascot behavior, or window tracking.

For a new STT engine, follow [the separate speech-provider recipe](local-speech-models.md#extending-providers-and-models). Speech streams PCM and incremental timestamped phrases; text models consume bounded text and return one result. They share artifact storage and resource priority without pretending these are the same inference contract.

## Resource and failure behavior

One downloaded text model is loaded at a time. Each request starts a fresh prompt cache. Chat reconstructs native conversation messages from its bounded working context; meeting tasks remain independent. Input is checked against a 4,096-token total context and generation is limited to 1,400 tokens (individual tasks use smaller limits). MLX uses the model-specific allocation budget described above, with a 128 MiB cache. These limits do not describe total process RSS or all driver allocations.

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

Use another catalog ID, such as `qwen-3.5-2b`, `qwen-3.5-9b`, `gemma-4-e4b`, `gemma-4-26b-a4b`, or `ministral-3-8b`, to check another model. The benchmark loads the installed files offline through `DownloadedReasoningBackend`, including the same JSON shaping and fence handling used by the app. It checks three short English/Romanian/mixed-language outputs against required source facts, prints request-to-result timings, and shuts the runtime down. It is a smoke check, not an accuracy leaderboard or a guarantee of interactive latency on other Macs.

The helper also accepts `--check-tokenizer /path/to/pinned-local-files` for a small multilingual round-trip/chat-template check and `--self-test` for bundled GPU-kernel validation. Neither command downloads anything.

Model quality cases belong in `Tools/TextModelBenchmark/TextQualityFixtures.swift`, not in provider-specific production heuristics. The benchmark checks required facts and prints every output for semantic review. Runtime schema/evidence checks cannot guarantee that a generated summary is factually correct.

Development checks on an M4 Pro with 48 GB (debug build): all six pinned tokenizers/templates passed the multilingual round-trip check. Full-weight Qwen3.5 4B runs took roughly 12–23 seconds for the first request including hash verification/loading, then 1–1.4 seconds per short warm request. Qwen3.5 2B took about 3.6 seconds for the first request and 0.7–0.9 seconds for subsequent short requests. Both preserved the monolingual Romanian/English fixture facts but changed a weekday in the mixed-language fixture, which the quality check reports as a failure. No production weekday workaround is used. The remaining models, including Gemma 26B, have not received full-weight quality/performance evaluation; successful catalog/tokenizer checks do not certify their summaries.
