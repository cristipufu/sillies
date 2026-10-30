# Audio capture and transcription

This target depends on Core and the local echo-cancellation library. AppKit, SwiftUI, persistence, preferences, windows, and application globals stay outside it. Expose only the capture/language contracts with `package` access; keep recognizers and DSP internal. Add audio-only tests in `Tests/SilliesAudioTests`, using `SilliesAudioTestSupport` for shared language fixtures.

- Device callbacks submit immutable retained packets to `AudioCaptureInputQueue`; never perform DSP, transcription, or disk I/O in the callback. The queue enforces duration, count, and byte bounds and reports overflow once.
- `AudioTranscriptionService` owns the serial capture queue and finalization. Its lifecycle Mutex covers startup/stop across queues. `SessionSpeechPipeline` and `SpeechChannelGroup` assert that same queue at their entry points. Recognizer outputs return to it and must match the active generation.
- Failure callbacks may cancel a channel immediately. Invoke them after releasing locks. Finish/cancel must tolerate duplicate or late native callbacks, cancel preparation, and release staged audio.
- Keep Apple SDK concurrency exceptions limited to documented owners in `Tools/ArchitectureCheck/UncheckedOwners.json`. Prefer checked `Sendable` and `Mutex<State>`; do not add unchecked conformance just to silence the compiler.

Example: a new microphone failure originates in `MicrophoneAudioSource`, becomes a capture update, and is rendered by the app. It must not directly update a view or save a vault record. A language switch drains the old group, buffers a bounded amount of audio, and installs a new generation without restarting recording.

Run `make stress` for accelerated queue/memory/scroll/lifecycle checks (90-second execution watchdog; compilation is separate), and `make check` for integration. No multi-hour wall-clock test is required. Real ASR integration is optional and uses a short prerecorded fixture; do not prompt for device permissions in default tests.
