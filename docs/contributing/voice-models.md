# Add a voice / TTS model

Voice providers turn bounded text into mono PCM. Chat owns the conversation; it never imports an
inference SDK. Recognition, reasoning, synthesis, playback, and artwork have separate owners.

## Add a model to an existing provider

1. Check the pinned runtime's architecture, tokenizer, codec, voice, and language support. Check the
   model's license separately from the runtime license. A model card alone does not prove that a
   particular native runtime supports every advertised feature.
2. Add the pinned components to `scripts/update-tts-catalog.py` and regenerate
   `Sources/SilliesModelStore/Resources/tts-models.json`. Include every pronunciation file, tokenizer,
   codec, and voice resource. Each artifact needs an immutable revision, size, and SHA-256 digest.
3. Set truthful language, memory, voice, and streaming capabilities. Do not advertise fixed voices
   for a model that generates a different voice on each request.
4. Validate a complete installation with networking denied. SDKs must not silently download missing
   support files during generation. Downloading and selecting remain separate user actions.
5. Run short real-audio checks in the languages you intend to support. Check intelligibility,
   pronunciation, first-audio latency, memory, and cancellation. Keep ordinary tests independent of
   network access and downloaded weights.

## Add a provider

- Implement `TTSProvider` and `PreparedTTSModel` from `SilliesTTS`. Preparation consumes a verified
  local directory; it must not initiate downloads. Await the audio sink to preserve backpressure.
- Implement `prepareVoice` to load the requested voice/language before text is ready. Repeated calls
  for an unchanged, reusable voice must reuse native state. The adapter owns cache invalidation;
  one-shot session state must be consumed/reset rather than leaking previous text into a new phrase.
- Put the runtime in `SilliesTTSInference` or a focused target reachable only from that helper.
  Register the provider ID in `VoiceServices` and its runtime factory in `TTSInferenceMain`.
  The app only receives validated, bounded PCM through the existing process transport.
- Reuse `TTSModelRegistry` for installation leases, inference admission, stop, and idle release.
  Microphone recognition preempts voice generation; voice generation preempts background text work.
- Keep native inference off the main thread. Cancellation must kill and reap a non-cooperative
  worker. A runtime crash must preserve the written reply and leave later turns usable.
  The helper's parent-exit monitor must remain active even during a stalled native call.
- Reuse `VoicePlayback` for bounded buffering and playback-level notifications. Character artwork
  observes these levels; it must not own an audio device, inference task, or timer.
- Preserve the output Audio Unit post-render callback used for Chat's echo reference. Queued synthesis output is not a
  substitute for rendered samples: cancellation and device latency would misalign it. Chat keeps
  AEC/VAD live during playback and acquires recognition priority per utterance; a provider must not
  pause the microphone or bypass shared cancellation when the user interrupts.
- Keep reference timestamps on the output presentation clock and preserve resampler stream continuity.
  Mixer tap batch sizes are not render quanta; a tap can delay the reference or miss a short utterance.
  Exercise different input/output rates and packet sizes without device-specific fixed offsets.
- Update package/import boundaries, their negative fixtures, packaged resources, and notices.
  Do not add a community runtime package as a shortcut: the current dependency policy is to use the
  existing runtimes or maintain a focused native implementation within this repository.

## Incremental replies and playback

`ChatTurnOperation` owns and joins the text and voice branches. `ChatTurnStream` coalesces presentation
updates and assembles bounded phrases through the pure `SpokenPhraseBuffer`. `SpeechTextStream` is
one bounded reply with one reader; it can hold the complete reply while a large voice waits for text
generation to release memory. This avoids a backpressure deadlock between inference branches.

The first text delta starts speculative voice preparation while phrase assembly continues. Admission
must never preempt active reasoning to warm a voice: defer when memory or another interactive task
prevents overlap. New incompatible text or recognition can cancel preparation without failing the
spoken reply. Synthesis subsequently uses the ordinary admission path. Helpers run at interactive
priority, with native work outside the UI process.

Opening phrases use a shorter word/clause boundary than later phrases. A finite 350 ms deadline can
release at least 20 complete characters during slow, unpunctuated output; it never cuts a partial
word. Later chunks retain the existing 180-character bound. Keep segmentation pure and the deadline
owned/cancelled by `ChatTurnStream`, including text failure and voice-only cancellation.

`SpeechModelLifetime` keeps the single selected voice runtime available while Chat is open. The
registry owns the 60-second idle eviction schedule; active lifetimes defer eviction, while memory
pressure or an incompatible model reservation can reclaim it. Closing Chat ends its lifetime;
pause/termination stop the environment and its memory-pressure subscription. Helpers have no second
idle timer that can silently discard an otherwise retained runtime. Parent-death, request deadlines,
and explicit cancellation remain mandatory.

`ChatSpeechPlayer` starts one playback session for the turn, synthesizes phrases in order with the
same selected voice, and drains playback once at the end. Pocket and Qwen emit native audio chunks;
Fish decodes groups of generated codec frames incrementally. Kokoro completes a short phrase before
emitting its audio. Its `streamsAudio` capability therefore remains false: phrase streaming does not
make the underlying model autoregressive. Pocket currently starts a native utterance for each phrase;
this is not a persistent duplex text-input session, and phrase boundaries can affect prosody.
Fish currently has no reference-voice conditioning, so its automatic voice may vary between phrases.
Streaming does not guarantee real-time generation; slower models can still leave playback gaps.

Await every audio sink. Helper acknowledgements propagate the player's 0.75-second buffer limit
back to synthesis. `markUtterance` associates the phrase with its final hardware buffer; only actual
playback completion marks it as spoken. Duplicate, reordered, and stale callbacks cannot acknowledge
new audio. Output-configuration changes stop the current playback session. A single actor-owned
watchdog detects a device that stops completing buffers, releases blocked producers/drains, and is
cancelled on every playback stop. It does not run on the UI actor. Device adapters report failures
through `onInterruption`; the player cancels synthesis immediately even if it is waiting for a native
model rather than blocked on an audio buffer. A partly played phrase is conservatively absent from the completed-phrase prefix.

Latency milestones distinguish phrase readiness, voice preparation, first PCM, and first non-silent
device output. `onAudibleOutput` uses the post-render presentation timestamp, skipping leading
silence; scheduling a buffer or starting the speaking animation is not evidence of audible output.
Callbacks retain playback-generation ownership. This measures device presentation, not room sound
or whether the user muted the speakers.

A voice error stops that branch while written output continues. Text failure or interruption cancels
both branches, retains the partial bubble, and never retries already delivered speech automatically.
Turn IDs reject late callbacks. Keep the rendered-audio echo reference and microphone interruption
path active throughout. Test first phrase before final text, queue exhaustion, cancellation while
waiting for memory or playback, and a voice failure during continued text generation.

## Native Fish implementation

`SilliesFishSpeech` implements S2 Pro inference with the existing Apple MLX and Hugging Face tokenizer
dependencies. There is no Python runtime, local server, or `mlx-audio-swift` package dependency.
Its scope is the pinned 8-bit model, text prompting, dual autoregression, and decode-only S1 DAC.
Reference-audio encoding, voice cloning, and training are outside this implementation.

Configuration validation, tensor operations, attention caches, sampling, prompting, and the audio
decoder have separate files. Mutable tensors stay inside the helper's actor. Package checks prevent
the app and feature targets from depending on this runtime. Model generation has a bounded context
and frame count; exhausting the limit is a recoverable failure, not silent truncation.
The decoder retains bounded causal convolution history and a 128-frame attention window, resetting
between utterances. Numerical tests compare chunked convolutions against independent references and
chunked attention against whole-sequence decoding across the window boundary.
The helper limits MLX command buffers to eight operations, the reusable allocation cache to 128 MiB,
and MLX allocation admission to at most 12 GiB or half of physical memory. These protect compositor
headroom; they are not a peak-process-memory guarantee. Preserve these controls when changing the
runtime, and exercise native move/resize/switch/drag budgets during a complete synthesis request,
including codec decoding. Off-main execution alone does not establish smooth interaction.

The implementation was informed by Fish Audio's published architecture and the MIT-licensed Swift
reference. Attribution and the separate model terms are in [third-party notices](../../THIRD_PARTY_NOTICES.md).
The conversion is downloaded as data; it does not execute code from the model repository.

## Checks

Run headless `make check BUILD_DIR=/tmp/sillies-check` and relevant cancellation/race checks.
The explicit `make gui-check` suite covers Chat activation, close/reopen, stacking, and exclusion
from mascot attachment. Routine checks also kill a fixture caller while keeping the helper's input pipe open, verifying that parent
death alone terminates the helper. Thread Sanitizer runs Swift Testing in two disjoint groups of
bundles, then XCTest and the audio signal matrices separately. Each run has a 90-second execution
watchdog; compilation is outside those deadlines. The groups retain all selected tests and each run
verifies completion receipts against discovery.
The app, capture, admission, process transport, and playback tests remain instrumented. Fish's GPU
numerical suite runs in normal `make check` and the real-model checks: MLX's own
[build configuration](https://github.com/ml-explore/mlx/blob/main/CMakeLists.txt) rejects Thread
Sanitizer on macOS. Instrumenting its Metal completion bridge produces a vendor-level diagnostic even
for a single matrix operation. No application race suppression is installed, and the vendor report
is not evidence that all native GPU internals are race-free.

For an opt-in real model check:

```sh
source scripts/toolchain.sh
swift build --product SilliesTTSInference
swift build --product TTSBenchmark
.build/debug/TTSBenchmark install MODEL_ID /tmp/sillies-voice-check
python3 scripts/run-bounded-test.py 180 /usr/bin/sandbox-exec \
  -p '(version 1)(allow default)(deny network*)' \
  .build/debug/TTSBenchmark run MODEL_ID /tmp/sillies-voice-check
```

Installation is separate from the bounded inference test. Inspect/listen to the generated WAV;
non-silent PCM alone does not establish speech quality. Optional final arguments are a language code
and a short passage. Test the packaged helper too, since command-line execution does not establish
that all Metal and runtime resources are bundled correctly.
Set `SILLIES_TTS_HELPER` to the absolute packaged helper executable to run the same check against it.
The runner reports first PCM separately from total synthesis time. Replace `run` with `latency` to
compare a cold helper, explicit voice preparation, and two successive requests with retained state.
Each phase writes a separate WAV. These sink measurements exclude text generation and device output;
do not report them as end-to-end conversational latency. No download is performed by `run` or `latency`.
