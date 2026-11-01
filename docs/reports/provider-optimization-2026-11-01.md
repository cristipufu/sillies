# Provider optimization validation — 1 November 2026

This pass checks the adapter opportunities identified after the Fish profile. Changes are retained
only when their correctness checks and available measurements support them. The machine used for
native measurements was an M4 Pro with 48 GB of memory, running macOS 26.7.2. Timings describe these
bounded fixtures, not every model, language, machine or live conversation.

## Retained changes

| Area | Change | Evidence |
| --- | --- | --- |
| Nemotron STT | Exclusive, language-keyed decoder leases; reset after draining native work; retain at most two idle engines | Cancellation, failure and source-isolation tests. Two simultaneous English sources transcribed correctly twice. First explicit-language channels took 66/68 ms to prepare; reused channels took 15/3 µs. Automatic-language preparation remains a separate initial cost. |
| Apple STT | Interactive priority reaches SpeechAnalyzer, its result consumer and finalization | Priority mapping regression passes. Native measurement was attempted but the required analyzer assets were unavailable; no latency gain is claimed. |
| Whisper / Parakeet | Reuse a complete draft only when finalization receives unchanged audio; cache Whisper dictionary tokens per tokenizer | Integration test checks one decode for opted-in complete-window engines and two for flush-required engines. Changed audio still decodes. Native Parakeet transcribed two fixture turns correctly, finalizing in 46/57 ms. Whisper weights were unavailable; dictionary reuse/change/clear and Unicode are covered with an injected encoder. |
| Downloaded text models | One bounded exact tokenization shared between input measurement and generation | Same 823-token input in 20 measurements: median 9.84 ms before, 0.124 ms after. Native self-check covers exact output, changed input/context and cancellation. No inference tokens are skipped. |
| Text-model residency | Explicit chat lifetime, pressure-aware registry retention, revision-aware identity | Idle retention, lifetime end, pressure eviction, preemption and cancellation regressions. Helpers have no separate idle expiry; parent death still terminates them. |
| Apple text | Retain one exact completed native conversation continuation | Through the application adapter, three identical follow-ups took 382/367/370 ms with reuse versus 670/660/654 ms rebuilt. All returned the expected fixture fact. Tests cover edited history, failures, pressure, session end and turn-local tool routing. |
| Audio output | Prepare the device concurrently with voice preparation once text starts | Silent hardware test measured 95 ms for device preparation and 8 ms to enqueue afterward. Render-clock, short-utterance echo-reference and stop checks pass. This moves setup before first PCM; it is not an end-to-end audible-latency measurement. |
| Kokoro | Cache rebuildable metadata and convert only the selected JSON voice; shipped binary voices bypass conversion | Three paired runs: median provider preparation 637 ms before, 356 ms after, excluding installation verification. All 15 paired WAVs were byte-for-byte identical. Corruption, changed source/version, symlink and size tests pass. Packaged self-check covers both binary and JSON voices. |

Kokoro preparation comparisons use the same warmed installation path. Its first run in a newly cloned
model directory took 14.5 seconds; that includes native cold preparation and is **not** used to claim
an optimization gain. Warm first PCM stayed around 73–83 ms. Changing from the binary voice to a JSON
voice and back succeeded offline in one runtime.

## Investigated changes not retained

**Downloaded LLM KV reuse.** A native MLX ChatSession experiment reused zero of 872 prompt tokens for
Qwen3.5 2B. Its template removes the empty thinking block from historical replies, requiring rewind;
the hybrid recurrent cache cannot perform that rewind. Native fallback was correct, and latency did
not improve (roughly 474 ms reused versus 464 ms rebuilt in the first pair). The experiment was
removed. No template changes, fabricated histories or unsafe recurrent-state reuse were retained.
Other text architectures were not available locally for a validated KV improvement; this pass does
not claim KV reuse across downloaded models.

**Persistent Pocket session.** The pinned API exposes utterance indices but no per-utterance completion
event. The frame stream finishes only after the whole session is finished, and uses an unbounded native
stream. Removing `finish()` would break the app's phrase-completion contract. Existing native voice
snapshots already avoid repeated neural voice prefill: warm voice preparation measured about 1–3 ms;
warm first PCM was 42–56 ms. Keep bounded per-phrase completion until the runtime provides an explicit
completion boundary and bounded delivery. No silence-gap guessing was introduced.

**Additional Qwen TTS prompt caching.** The adapter and pinned runtime already cache prompts and match
voice, language and instruction before reuse. Voice switching and switching back produced valid audio
offline. Warm first PCM was 72–79 ms in this fixture. No duplicate cache was added; multilingual audio
quality was not assessed by these timing checks.

**Persistent idle audio engine.** Early preparation removes setup from first-PCM delivery while keeping
existing output-device, interruption and echo-reference ownership. Holding an engine between replies
would introduce an additional device lifetime without a demonstrated benefit over this overlap. The
engine still stops at completion and cancellation.

**Kokoro silence trimming.** The fixture crosses the playback signal threshold after 6,896 samples
(287 ms at 24 kHz), but contains nonzero audio before then. The pinned pipeline returns the learned
alignment/vocoder waveform directly, with no adapter-added leading padding. A threshold alone cannot
prove that quiet phonemes are disposable. The waveform is preserved.

**Reducing STT partial cadence.** No quality evidence justifies fewer partial predictions. The retained
change removes an identical final prediction only when the engine explicitly guarantees that its draft
is complete; incremental engines still flush.

## Ownership and extension contracts

Caches stay with their model, tokenizer or native backend. There are no global model caches, per-turn
polling timers, automatic downloads, new runtime dependencies or UI-thread inference. The shared
inference lifetime supports explicit end notifications, and pressure eviction takes precedence over
idle retention. Apple tool routing is scoped to one current toolbox. The subsequent
[Chat investigation](chat-reliability-2026-11-01.md) extends native continuation across completed tool
turns, validated against exact canonical exchanges. New derived-file and device-preparation entry
points keep worker assertions.

Contributor contracts are documented in [speech models](../contributing/speech-models.md),
[text models](../contributing/text-models.md) and [voice models](../contributing/voice-models.md).
The [machine-readable checklist](provider-optimization-2026-11-01.json) records every audit item,
including rejected experiments and validation limitations.

Native tests used prerecorded audio or silent device output. No microphones, visible GUI checks,
model downloads or multi-hour soak were used. The running app was not restarted.

## Final checks

`make check BUILD_DIR=/tmp/sillies-provider-check` passed with 560 receipt-verified headless tests,
packaged GPU/helper self-checks, parent-death checks and catalog validation. The final architecture
pass passed 84 fixtures and 16 package-boundary fixtures, including enforcement for the new derived
artifact and output-device preparation entry points. Release build: `/tmp/sillies-provider-final/Sillies.app`.
Changes remain local, uncommitted and unpushed.
