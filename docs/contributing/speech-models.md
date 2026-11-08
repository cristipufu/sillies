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
