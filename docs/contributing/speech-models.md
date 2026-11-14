# Add a speech model or STT engine

Speech providers turn worker-owned PCM into timestamped draft and final phrases. They do not own the
microphone, the transcript window, or the mascot. A compatible model is a catalog addition; a different
inference runtime needs a provider adapter.

## Add a model to an existing runtime

1. Check architecture, tokenizer, language-control behavior, license, and memory requirements against
   the pinned WhisperKit or FluidAudio version. Sharing a model family name is not proof of compatibility.
2. Extend `scripts/update-speech-catalog.py` with the pinned upstream revision and model metadata.
   Generate `Sources/SilliesModelStore/Resources/speech-models.json`. Include every required file,
   tokenizer, exact byte length, SHA-256 hash, license, and hardware/language capability.
3. Keep the model ID stable. Revisions identify immutable files; do not silently substitute different
   weights under an existing revision. Update catalog expectations and packaged attribution.
4. Verify offline preparation and recognition before exposing the model. Check claimed languages with
   actual speech, including English, Romanian, names, diacritics, and mixed-language phrases.

After editing the generator, regenerate and inspect the manifest:

```sh
python3 scripts/update-speech-catalog.py
git diff -- Sources/SilliesModelStore/Resources/speech-models.json
```

This maintenance step uses the network for upstream metadata and small support files; it does not
download model weights. Review the generated license and capability fields for the new model.

The shared installer and settings presentation consume the catalog. A compatible model should not
require new capture, download, or settings code. Some runtimes need an explicit decoding/configuration
adapter even when the files install correctly.

## Add a runtime

1. Create an adapter target implementing `SpeechProvider` and `PreparedSpeechModel` from `SilliesSpeech`.
   Register it once in `SpeechServices`, and use its provider ID in the catalog. Duplicate speech or
   diarization provider IDs are rejected at startup instead of silently choosing an adapter.
2. Keep the SDK dependency inside that adapter; update the package and architecture policy accordingly.
   Do not import it into Core, views, capture, or model storage.
3. Give each audio source independent bounded recognition state while sharing immutable weights.
   Serialize native inference correctly across suspension points. Window-based engines can reuse
   `WindowSpeechModel`. For incremental decoding, `WindowSpeechChannel` also supports `.streaming` cadence and supplies `SpeechWindowPosition` with every request. `SpeechIncrementalWindow` identifies new samples and mandatory resets. See `SilliesSpeechNemotron`: each source gets a separate decoder, while shared buffering bounds even SDK-owned transcript history. Preserve the final drain and the overlapping boundary timestamps.
4. Implement drain and cancellation, incremental timestamps, language controls, and supported vocabulary
   hints honestly. If the runtime requires a minimum audio duration, handle short final windows without
   inventing transcript time. Do not retain the full recording or use an SDK helper that owns capture.
5. Load only verified local artifacts. Disable every automatic network fallback, including tokenizer
   downloads. Reuse installation leases, progress, errors, and teardown from the shared infrastructure.

`SpeechProvider.languages(_:)` owns language discovery. Downloaded adapters inherit the implementation
that combines catalog capabilities with installation availability. Override it for system-managed assets
or runtime-specific discovery; discovery must not install assets or prepare a recognition model. Check
cancellation before preparation or discovery starts. The registry selects the provider and owns leases;
it does not call a particular provider's discovery implementation directly.

Preparation waiters must cancel without awaiting an uncooperative native load. The registry keeps
one pending native load per identity until it returns, rejects duplicate retries during cancellation,
and discards cancelled results. Apple Speech can still prepare while a downloaded model is loading.
Talk reports speech preparation separately from microphone setup and bounds startup to 45 seconds;
late success must never reopen a stopped microphone. Use the startup/cancellation regressions and
the opt-in `downloadedConversationStartupReachesListeningAndReleasesAdmission` check with
`SILLIES_CONVERSATION_STARTUP_CHECK=1` and `SILLIES_STT_STORE` pointing to a verified local installation.
That check exercises the actual Parakeet warmup chain with a fake microphone and no room capture.

Speaker detection is a separate capability with `DiarizationProvider` and `PreparedDiarizationModel`.
Do not imply an STT engine identifies speakers just because its transcript has source labels.

## Check it

Run `make check BUILD_DIR=/tmp/sillies-check`, `make stress`, and `make race-check` as applicable.
Cover both audio channels, silence, window boundaries, short final chunks, overload, language changes,
cancel/restart, and offline failure. Default tests must not download weights.

Add the adapter/model pair to `SpeechProviderContractTests` and reuse `verifySpeechProviderContract`.
It exercises installed/missing language availability, unsupported-language handling, and cancellation
before model loading. Keep each model's language acceptance cases explicit; the bundled fixtures cover
English/Romanian providers. Runtime channel tests must additionally cover draining and cancellation during
active inference, using a fake engine in the normal suite and short real-model checks when opted in.

Use the [bounded real-model benchmark](../local-speech-models.md#short-validation) for short, consented
English and Romanian fixtures. Separate download/preparation from the timed inference run. Evaluate
recognition quality independently of whether the adapter successfully produced text.

See [provider contracts, installation, diarization, and updates](../local-speech-models.md) and
[the development contract](../../AGENTS.md). For text generation, use the [text-model guide](text-models.md).

## Reusing recognition work

`SpeechEnginePool` leases stateful decoders exclusively by language. Release joins outstanding native
inference before resetting; failed decoders are discarded. Keep the idle pool bounded and owned by the
prepared model. Two simultaneous audio sources must never share a decoder's mutable history.

Complete-window engines may declare `.reuseUnchangedDraft` only when their draft already decodes the
whole supplied buffer and finalization adds no native work. `WindowSpeechChannel` then reuses an exact
unchanged final window. Incremental engines keep the default `.decode` policy so their final flush is
never skipped. Preserve this capability through decorators. Partial-transcript cadence is independent
of this optimization. Whisper's dictionary prompt cache belongs to its loaded tokenizer and is reset
on a tokenizer change. Honor `SpeechRecognitionContext.priority` in native and consumer tasks.

## Recovering live recognition

Recording and recognition have separate lifetimes. `SpeechCapturePreparation` injects a private
`SpeechAudioBackingStore` into recording channels. `DiskSpeechAudioStore` owns four-second PCM pages
on workers, bounds each source to 64 MiB on disk, and deletes committed pages and the remaining
session backlog on completion or cancellation. The 24-second recognition memory bound is unchanged.
Neither audio nor recognized text enters diagnostic events.

`WindowSpeechChannel` retries the same window after transient inference failures without committing
its draft or resetting transcript positions. Busy inference uses capped exponential backoff; other
errors have three attempts. Catch-up skips intermediate drafts when a complete window is queued,
retains overlap until words commit, and reports typed recovery transitions per source. Wrappers must
forward `onRecovery`; UI recovery remains active until both meeting sources catch up. Permanent
failures and exhausted disk bounds remain explicit failures while the independent AAC recording
continues. Meeting capture owns one 30-second finalization budget for recognition, speaker labels
and completion delivery; microphone-only capture retains its eight-second budget. Device stops
begin immediately. Channel groups retain their bounded language
switch deadline, but session shutdown supersedes it and has no competing child deadline. A failure
and a later Finish subscribe to the same device stops. Finalization timeout must not be presented
as successful transcription, and diagnostics identify the resources that did not finish.

A verified bound-window closure finishes and saves a meeting automatically, including its final
recognizer drain. Hiding, minimizing, or temporarily failing to read a window does not end capture.
`SessionEndReason.sourceClosed` explains a capture interruption before finalization begins; permission,
transcription, timeout, and recording-save failures still retain their recovery information.

## Qualify boundary policy changes

`SpeechBoundaryPolicy` in Core owns bounded, per-source acoustic classification. The window buffer
owns audio and utterance retirement. `SpeechRecognitionContext.windowBoundaryMode(for:)` selects the policy from capture purpose and an
immutable `SpeechWindowConfiguration` at channel creation. Both `WindowSpeechModel` and the direct
streaming adapter use that path. Providers supply qualified policy values and own native decoding;
they never implement thresholding, calibration, buffering or utterance retirement. The default
configuration retains baseline boundaries. Parakeet explicitly opts into its qualified adaptive
policy. Whisper and Nemotron retain baseline boundaries because native qualification found
noise, subgroup or critical-word regressions. Apple already forwards all audio to its analyzer
and has no local energy gate.
`SpeechRecognitionContext.purpose` distinguishes continuous transcription from short utterances
independently of inference priority. Short Talk/dictation channels keep their established policy.
A request override exists for paired qualification; no user setting or persisted preference is added.

Use the [file-only native quality runner](../../Benchmarks/Speech/README.md) before changing the shared
policy. Compare the same weights, language and decoder on development speech, freeze the
candidate, then evaluate unseen human recordings, paced delivery, short replies, silence and long
speech. Keep failed results. Do not generalize a provider's result to other runtimes or every language.
Window and inference observers must remain optional, typed and content-free, outside audio locks and diagnostics
archives; they must never record audio, words or tokens.
