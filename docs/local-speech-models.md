# Local speech models

The first catalog contains Whisper Large v3 Turbo compressed (WhisperKit, approximately 629.5 MB including tokenizer) and Parakeet Ultra (FluidAudio, approximately 632.3 MB). Apple Speech remains the default. Downloadable engines require Apple Silicon. Package versions and every model artifact revision/hash are pinned; downloading weights does not download executable plugins.

Parakeet offers automatic detection and optional language hints. FluidAudio 0.18.0 uses hints to filter decoder tokens by script; Romanian and English share the Latin script, so a hint does not strictly force one over the other. Keep this distinction in the capability metadata and language controls. The provider pads final windows shorter than the runtime's 300 ms minimum with silence; transcript timing and retirement still use the original audio length.

Model transfers use explicit URLSession download tasks: the async convenience download API does not reliably deliver intermediate delegate byte callbacks on macOS. Progress measures aggregate artifact bytes, switches to verification before hashing each file, and returns to downloading before the next file starts. Core ML preparation is a separate indeterminate phase. Loopback HTTP tests cover actual progress, cancellation/resumption, and oversized responses without downloading weights.

Speech recognition and text summarization have separate language coverage. Apple Foundation Models supplies generated notes only for locales supported on the current Mac. Optional [downloadable text models](local-text-models.md) provide an independent multilingual choice in Settings → Local AI. Otherwise the Vault saves source excerpts with explicit extracted-highlight provenance; these are not AI summaries. Saved older records without provenance retain a neutral notes label.

## Extending providers and models

1. For another compatible model, add an exact artifact manifest to `Sources/SilliesModelStore/Resources/speech-models.json`. Record all required files, including tokenizers, exact byte lengths, SHA-256 hashes, licenses, languages, and hardware requirements. `scripts/update-speech-catalog.py` regenerates the built-in catalog from pinned upstream revisions and reads only metadata/small tokenizer files.
2. For another runtime, add an SDK adapter target implementing `SpeechProvider` and `PreparedSpeechModel`. Register it once in `SpeechServices`. Keep SDK imports out of audio capture, Core, views, and the model store. Add its allowed imports to `ArchitecturePolicy`.
3. A channel accepts worker-owned PCM, emits timestamped drafts/finals, and has explicit drain/cancel paths. Use `WindowSpeechModel` for window-based recognizers. Maintain independent source state while sharing immutable weights; serialize predictions across async suspension points.
4. Do not use SDK streaming helpers that own the microphone, retain the complete session, or create an unbounded input stream. The current adapters call the lower-level inference APIs.
5. Validate offline loading, both channels, language changes, repeated speech at window boundaries, silence, bounded overload, cancellation, and error recovery. Add dependency/model attribution to the packaged notices.

The Whisper adapter overrides tokenizer loading because the SDK's `download: false` does not disable its tokenizer fallback. It constructs the tokenizer from local files and fails if they are incomplete. `OfflineWhisperKit` only changes loading; the SDK still owns decoding and alignment. The SDK's private model-variant diagnostic remains its default when supplying a tokenizer this way; multilingual decoding is set from the loaded vocabulary dimension. Recheck this contract when updating the pinned SDK.

## Installation and lifecycle

Models live under `~/Library/Application Support/Sillies/SpeechModels/<model-id>/<revision>`. Partial downloads are separate and are never selectable. Verified completed artifacts are reused on retry; URLSession resume data is retained when available. SHA-256 verification occurs before atomic installation and again when acquiring a runtime. Symlink/path traversal checks inspect every existing path component. A lease prevents removal/replacement while a runtime is preparing or in use.

The inference actors use explicit serial worker executors. Large runtime allocations are released through isolated actor deinitializers, so ending a session cannot move model destruction onto the UI caller. Whisper runs the small mel transform on CPU and its large models on CPU/Neural Engine to leave the GPU available to the compositor.

The first Core ML preparation can take substantially longer than later loads. It runs off the UI thread. Cancellation rejects results and requests SDK cancellation; a native Core ML call already in progress may finish before memory is released. Settings exposes this as cancelling and does not start another conflicting operation. No synchronous wait on the main actor is allowed.

## Short validation

Default tests require no model download or device permissions. `make check`, `make stress`, and `make race-check` cover boundaries, bounded virtual-duration audio, cancellation, and UI behavior. Accelerated silence coverage represents eight hours in seconds, without an eight-hour recording.

For optional real-model checks, build the standalone runner and keep download/preparation separate from the 90-second execution limit:

```sh
source scripts/toolchain.sh
swift build --product SpeechBenchmark
speech_benchmark="$(swift build --show-bin-path)/SpeechBenchmark"
"$speech_benchmark" install parakeet-ultra /tmp/sillies-stt-models
python3 scripts/run-bounded-test.py 300 "$speech_benchmark" prepare parakeet-ultra /tmp/sillies-stt-models
python3 scripts/run-bounded-test.py 90 "$speech_benchmark" run parakeet-ultra /tmp/sillies-stt-models /path/to/short-english.wav /path/to/short-romanian.wav
```

Substitute `whisper-turbo` for Whisper. The runner feeds each file to two simultaneous channels at capture speed, prints finalized transcripts, process footprint, and main-actor scheduling delay, and refuses fixtures over 30 seconds. Repeat the same fixture within one invocation to compare retained memory between channel lifecycles. The footprint belongs to the runner process; it does not include separate Core ML services or establish peak memory use. Scheduling delay is a proxy, not a rendered-frame latency measurement. Use real, consented meeting clips to assess recognition quality; synthesized fixtures are smoke tests, not a WER leaderboard.

The opt-in native test also runs AAC encoding, local notes, and all four mascot interaction budgets while both speech channels are active:

```sh
bash scripts/test-downloaded-speech.sh parakeet-ultra /tmp/sillies-stt-models
```

Build before applying the external 90-second execution watchdog. Cold specialization is a separate preparation stage. Measurements on the development M4 Pro / 48 GB do not establish performance on an 8 GB Mac.

## Optional speaker detection

Settings offers a separate 102.1 MB Nemotron 3 speaker-detection download. The FluidAudio adapter uses the `fast32-split-w8a8` Core ML variant, supporting up to eight anonymous speaker slots per audio source with approximately 2.9 seconds of input context. It works alongside Apple Speech, Whisper, or Parakeet. Numbers belong to a source and session: microphone Speaker 1 is not necessarily Meeting Speaker 1. Speakers can be named per saved recording; voice enrollment and cross-recording identity are not implemented.

`SilliesSpeech` defines `DiarizationProvider`, `PreparedDiarizationModel`, and `SpeakerDiarizationEngine`; `SilliesDiarizationNemotron` owns the SDK. The actor shares weights and serializes native access, while each source owns independent bounded speaker-cache state. `StreamingDiarizationChannel` admits at most 16 seconds of pending mono PCM. `SessionDiarization` retains at most 64 final phrases / 16,384 characters awaiting activity. `SpeakerActivityTimeline` keeps only 6,000 recent frames, not a meeting-length history. Labeling errors/overload leave recording and transcription running. Finish and cancel share the existing asynchronous channel-group drain and timeout.

Word timestamps split final text at speaker changes; incomplete timing metadata preserves the original words with an uncertain label. Drafts stay visible without premature finalization. Speaker state survives ASR language switches, and replayed recognizer audio is not fed twice into speaker detection. Overlapping voices are marked explicitly. Saved records include the speaker-model revision in addition to ASR provenance.

A short natural-speech fixture from [pyannote's tutorial assets](https://github.com/pyannote/pyannote-audio/tree/develop/tutorials/assets) distinguished returning speakers and overlap during development. Repeated macOS synthetic voices exposed incorrect speaker merges in both the SDK batch reference and streaming paths. These are smoke checks, not a diarization accuracy benchmark; Romanian meeting accuracy has not been independently scored. Labels can be wrong, and the UI says so. No multi-hour native recording test is required.

Run the speaker benchmark with `nemotron-speakers` and a prerecorded file no longer than 30 seconds. To exercise two ASR streams, two diarization streams, AAC recording, local notes, and native mascot budgets together:

```sh
SILLIES_DIARIZATION_MODEL=nemotron-speakers bash scripts/test-downloaded-speech.sh parakeet-ultra /tmp/sillies-stt-models
```

## Automatic update discovery, explicit installation

A published Sillies-approved revision feed is not required. The bundled catalog defines supported runtimes, model families, artifact paths, languages, and licenses. The application checks the [Hugging Face metadata API](https://huggingface.co/docs/hub/api) for the repositories already named by installed artifacts. It compares artifact hashes, including separately versioned Whisper tokenizers, so a README-only commit does not trigger an update. Missing required files require an app update; new support files within an existing compiled bundle are included. Every candidate URL is pinned to an immutable upstream commit and every artifact has a size/hash.

The check timestamp and results persist atomically. Automatic checks are enabled by default, happen at most once per 24 hours while the app is running, and can be disabled in Settings. One cancellable schedule checks whether work is due; there are no per-model timers. Pause, exclusions, and termination suspend it. Check now bypasses the daily interval. Only installed models are checked; metadata requests have size/time bounds. Audio and transcripts are never uploaded. Settings and the control center show available updates without requesting system notification permission.

Downloading an update is explicit. A candidate is staged beside the working version. `SilliesModelValidation` compares the installed and candidate Core ML input/output/state interfaces on a worker. The registered provider then loads the local files/tokenizer and runs a short inference smoke test. This verifies the actual runtime path, including operators and decoding; it does not establish recognition quality or peak memory on every Mac. Failed/cancelled validation leaves the current selection unchanged. An atomic selection pointer activates only after validation and only without active session leases. Model revisions captured for a session resolve to that exact retained version, so preparation races cannot mislabel provenance.

Use previous version restores the prior installation. Retries prune older completed versions while retaining the current, previous, and pending candidate. SDK/library updates and incompatible model architectures still require an app release. There are no silent weight downloads or hot swaps.

The optional native update test clones already-downloaded files into a temporary test store, compares native schemas, runs inference, activates, and rolls back. It never changes live app storage:

```sh
source scripts/toolchain.sh
swift build --build-tests
SILLIES_VALIDATE_MODEL_UPDATE=1 SILLIES_STT_MODEL=parakeet-ultra SILLIES_STT_STORE=/tmp/sillies-stt-models \
  python3 scripts/run-bounded-test.py 300 swift test --skip-build --no-parallel --filter nativeModelUpdateValidatesBeforeActivationAndCanRollBack
```

The standalone `SpeechBenchmark check MODEL_ID STORE_DIRECTORY` command queries live metadata without installing anything. Default tests use injected metadata/discovery/download clients, virtual dates, and temporary stores.


## Interactive speech and vocabulary

`SpeechRecognitionContext` carries vocabulary and an interactive priority independently of provider selection. Providers accept hints only through their native supported mechanism: Apple uses `AnalysisContext.contextualStrings`, and Whisper uses a bounded prompt. A common whole-word replacement pass applies the dictionary after speaker attribution for every provider. Preserve the raw acoustic words/timestamps until attribution completes.

`SpeechInferenceScheduler` prioritizes queued interactive work and raises its task priority. `SpeechWorkerExecutor` preserves that priority on its isolated queue; ordinary background work stays at utility priority. Neither priority nor cancellation guarantees preemption of a native prediction already in progress. Dictation has its own lifecycle, microphone-only channels, warm-runtime lease, cleanup deadline, and recovery history.

The pinned WhisperKit 1.1.1 runtime misaligns word timestamps when prompt tokens are present ([upstream issue 542](https://github.com/argmaxinc/argmax-oss-swift/issues/542)). `PromptAlignedSegmentSeeker` adapts the alignment matrix inside this provider, respecting Core ML row padding. Remove the adapter only after updating the pinned runtime and rerunning prompted English/Romanian/mixed-language fixtures. Zero-duration opening words remain valid and are covered independently by the rolling-transcript tests.

Use the runner's `dictate` command instead of `run` for one interactive channel with vocabulary hints. It reports **release-to-final-text**, separately from total duration. This excludes cleanup/insertion; the live dictation coordinator records release-to-insertion. First Core ML specialization can take about a minute on the development machine, and remains off the UI thread. Subsequent captures retain a recently used runtime for 120 seconds; idle expiry, pause, exclusions, and termination release it.
