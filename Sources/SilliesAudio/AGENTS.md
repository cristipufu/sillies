# Audio capture and transcription

This target depends on Core, provider-neutral SilliesSpeech contracts, and the local echo-cancellation library. AppKit, SwiftUI, persistence, preferences, windows, and application globals stay outside it. Expose only the capture/language contracts with `package` access; keep recognizers and DSP internal. Add audio-only tests in `Tests/SilliesAudioTests`, using `SilliesAudioTestSupport` for shared language fixtures.

- Device callbacks submit immutable retained packets to `AudioCaptureInputQueue`; never perform DSP, transcription, or disk I/O in the callback. The queue enforces duration, count, and byte bounds and reports overflow once.
- `AudioTranscriptionService` owns the serial capture queue and finalization. `AudioSessionLifecycle` in Core owns transitions and elapsed time. `CapturePreparation` cancels startup across queues. Capture, speech, channel-group, and microphone mutable state live inside `SerialQueueStorage`, which asserts the owning serial queue on every access and permits only Sendable results. Its state must never escape the access closure or be shared with another owner. Recognizer outputs return to it and must match the active generation.
- Failure callbacks may cancel a channel immediately. Invoke them after releasing locks. Finish/cancel must tolerate duplicate or late native callbacks, cancel preparation, and release staged audio.
- Keep Apple SDK concurrency exceptions limited to documented owners in `Tools/ArchitectureCheck/UncheckedOwners.json`. Prefer checked `Sendable` and `Mutex<State>`; do not add unchecked conformance just to silence the compiler.

Example: a new microphone failure originates in `MicrophoneAudioSource`, becomes a capture update, and is rendered by the app. It must not directly update a view or save a vault record. A language switch drains the old group, buffers a bounded amount of audio, and installs a new generation without restarting recording.

Preserve `SessionFailure` categories and recovery actions through capture updates, lifecycle state, and final results. Classify device authorization results or native error identities at the producer boundary; never select permission recovery by parsing localized error text. Unknown errors keep their diagnostic message without inventing a permission action.

Run `make stress` for accelerated queue/memory/scroll/lifecycle checks (90-second execution watchdog; compilation is separate), and `make check` for integration. No multi-hour wall-clock test is required. Real ASR integration is optional and uses a short prerecorded fixture; do not prompt for device permissions in default tests.

Repeated start is ignored; finish subscribers share one drain and cached result. Source IDs reject duplicate stop callbacks. Finalization retains its owner until completion or the bounded deadline, then releases it. Tests use `AudioCaptureDependencies` for devices, speech, queue, and virtual time; no real permission prompt belongs in lifecycle tests.

Use `make race-check` when changing queue ownership or callbacks. Its instrumented build is isolated from normal performance tests, and test execution is externally limited to 90 seconds. No race suppressions belong in application code.
