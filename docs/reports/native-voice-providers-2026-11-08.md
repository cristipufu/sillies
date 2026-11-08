# Native Woof and VibeVoice providers

November 8, 2026. Implemented on top of `750a086a9c4ca8a30d01cd272d48e69e936e40f2`.
Measurements use an Apple M4 Pro, 48 GB RAM, macOS 26.7.2. The input and result records are in
[the accompanying JSON](native-voice-providers-2026-11-08.json).

## Product choices

| Option | Download | Voices | Language exposed by this runtime | Decision |
|---|---:|---|---|---|
| Woof, int8 | 40.6 MB | Juno, Mira | English | Add as an optional download |
| VibeVoice Realtime 0.5B, 8-bit | 1.146 GB | Carter, Davis, Emma, Frank, Grace, Mike | English | Add as an optional download; retain the qualification limits below |
| VibeVoice, 4-bit candidate | 658 MB | Same six voices | English | Do not offer: observed incomplete short speech |
| NeuTTS Air | — | — | — | Skipped following the user's account-access decision |

Both offered models download anonymously. All synthesis and recognition checks below ran with
network access denied. No Python, community TTS runtime package, external server or model weights
are bundled with Sillies. Temporary development reference environments were used to validate the
native arithmetic; contributors can run the checked-in reference fixtures without those environments.

Woof's model and output retain the Underdog Non-Commercial License 1.0. The app displays the
required [Voice by Underdog Woof](https://underdog.ai) credit in Settings, setup previews, Chat and
Talk. Credit follows the actual playback model; stopped callbacks cannot replace it. VibeVoice uses
MIT terms, with Apache 2.0 tokenizer and scheduler notices. See [third-party notices](../../THIRD_PARTY_NOTICES.md).

## Architecture and failure handling

Each provider has a small `NativeTTSModel` adapter. The app-owned `SilliesWoofSpeech` and
`SilliesVibeVoice` targets run inside the existing killable synthesis helper. Package dependencies
and architecture fixtures prevent the numerical SDKs from entering the app or feature targets.
Inference, download verification and model loading remain off the main queue.

The providers reuse the existing catalog, verified installation, model retention, voice preferences,
inference admission, streaming acknowledgements and bounded playback. Woof reads a bounded numeric
NPZ archive using system zlib; it never extracts filesystem paths or accepts Python objects.
VibeVoice reads safe tensors and local tokenizer files. Immutable voice state seeds fresh attention
caches for every utterance; mutable decoder history resets on completion and cancellation.

Both runtimes enforce request, tensor, memory and generated-audio bounds. Exhausting the generation
budget reports an incomplete request instead of silently marking truncated audio successful.
Unexpected native tensor failures use the existing localized audio-error presentation. Cancellation
remains cancellation, and a voice failure preserves the written reply. No word-specific output
filters, forced minimum speech lengths or automatic quality retries were added.

## Why the 4-bit candidate was rejected

The short input was: **Hello! I am your little window companion.**

Two initially fast latency samples contained only the greeting according to local recognition.
A controlled six-seed Carter comparison reproduced that omission once. This was not attributed to
caching without evidence: repeating seed zero after intervening utterances, and in a fresh engine,
produced the same samples. Replaying seed one's exact noise inputs through independently dequantized
weights and Microsoft's reference components produced the same 35,200-sample stopping point;
relative waveform RMS error was 0.000208.

The 8-bit candidate retained the main sentence in all six corresponding seeded runs. Recognition
missed the greeting in two, so this is a narrow improvement, not perfect output or a statistically
established quality ranking. The corresponding seed-one reference replay produced the same
102,400 samples, with relative RMS error 0.000107. These full-sequence fixtures are now regression
inputs, alongside the component comparisons.

Microsoft documents its realtime model as primarily English and more focused on longer-form speech;
very short inputs can be unstable. That limitation does not excuse incorrect integration, which is
why the numerical and state checks were completed first.
[Publisher documentation](https://github.com/microsoft/VibeVoice/blob/16fb2cb1217c9934a886e1948ffb06120caa2df5/docs/vibevoice-realtime-0.5b.md).

## Speech content checks

Every offered voice generated both of these inputs through the production provider/registry/helper:

- **What would you like to talk about today?**
- **I found the notes from your meeting. We can review the decisions together, or look for a saved link.**

Parakeet Ultra recovered all expected words, ignoring punctuation, in all **16 completed samples**.
The final latency runs produced another **18 completed samples** of the greeting passage; all retained
its content, with one contraction (`I'm` for `I am`). These are small automated intelligibility checks,
not human listening scores or coverage of all pronunciation, numbers, languages and room conditions.
Woof's frontend handles typographic punctuation and bounded sentence/word splitting; it does not
include the publisher's full pronunciation/number rewriting system.

**One failed attempt remains in the evidence.** The first Emma question process exceeded its
45-second test deadline without publishing a final WAV. A repeat completed in 9.855 seconds.
Eight subsequent fresh-helper repetitions with chunk tracing all completed. The original process
was not sampled before termination, so its cause is unresolved; it is not counted as a successful
trial, blamed on the model, or claimed fixed. The qualification therefore had **15/16 first-attempt
completions**, with the remaining sample obtained on an explicitly recorded retry. No retry was
added to the product.

## Release timing

Three sequential observations per state and model, using the same greeting passage and a silent,
unpaced sink. Each trial starts a fresh helper, then prepares another helper, then reuses that
prepared model for a second phrase. No build or reference inference ran concurrently with this
measurement, but this was the user's active Mac, with normal background applications and previously
used OS/GPU caches. It was not a controlled clean-machine test.

| Model | Fresh helper: median first PCM | Prepared: median first PCM | Reused: median first PCM |
|---|---:|---:|---:|
| Woof | 331 ms | 69 ms | 43 ms |
| VibeVoice 8-bit | 2,067 ms | 246 ms | 95 ms |

These values measure the **first PCM callback**, including possible leading silence. They do not
measure first audible device presentation, text-generation time, or complete conversational latency.
The earlier 4-bit run is not a valid speed baseline: it had incomplete speech and different system
conditions. Warm VibeVoice synthesis took 2.63–3.53 seconds for 2.53–3.73 seconds of audio, so these
samples do **not** establish uninterrupted real-time delivery on every Mac. Existing playback
backpressure and cancellation remain essential. Woof is the lighter option in this test.

## Numerical and lifecycle validation

Woof matches the publisher's NumPy output for both voices on CPU and GPU, including after
cancellation. VibeVoice's text/speech stacks, diffusion sample and three sequential codec frames
match an independent Float32 reference, with relative RMS errors around 0.000003–0.000005.
The full utterance regression additionally checks exact sample count and a relative RMS error below
0.001. Checked-in fixtures include input/model/source revisions and SHA-256 provenance.

The final focused run verified **20 tests across two test bundles**, including the real models and
the exhausted-frame-budget regression (`run-c7d3b5ei`). The separate setup credit and Talk bubble
regressions also passed (`run-ptz0ke2u`). Tests never opened a microphone or output device.

`make check` passed all **1,100 selected tests**: 635 remaining-module tests, 46 audio tests,
87 persistence tests and 332 headless app tests. Completion receipts are `run-j8sqdd0q`,
`run-iug0b_b_`, `run-x9hn0sza` and `run-nk54p_pu`. Formatting, architecture boundaries,
localization, benchmark fixtures, GPU self-tests, catalog validation and helper parent-exit
checks passed as well.

The Developer ID-signed **release app's packaged helper** completed both providers' cancellation /
recovery and first-voice / last-voice / first-voice checks with network access denied. Cancellation
joined in 5.75 ms for Woof and 13.50 ms for VibeVoice; each following utterance completed. These
checks exercise valid streaming output and lifecycle ownership, not a human voice-quality score.

Packaging did expose slower first-use observations. A freshly built release bundle's Emma question
delivered first PCM after **14.18 seconds** and completed in 18.47 seconds; its subsequent recovery
utterance delivered first PCM in 2.16 seconds. These single observations are separate from the
warmed-path timing table. The debug bundle previously exceeded the 75-second recovery-check deadline;
a debug direct-helper probe completed in 31.91 seconds, versus 7.01 seconds for an unbundled debug
probe. The first debug probe also attempted process sampling, so this is not a controlled attribution
to optimization, App Nap, signing or compilation caches. The release lifecycle checks passed without
changing deadlines or adding a speculative scheduling workaround. Cold-start variance remains an
explicit limitation, not a promised warm-start time.

Visible GUI tests and human listening were not run. Prior broad stress/race timeouts from the
[microphone investigation](talk-startup-2026-11-08.md) are separate; these measurements do not waive them.

## Reproduce

Install a chosen model using `TTSBenchmark install MODEL_ID STORE_DIRECTORY`. The actual pinned
install directory is `STORE_DIRECTORY/MODEL_ID/REVISION`. Then:

```sh
SILLIES_WOOF_MODEL=/path/to/installed/woof-revision \
SILLIES_VIBEVOICE_MODEL=/path/to/installed/vibevoice-8bit-revision \
  bash scripts/test.sh --filter 'Sillies(WoofSpeech|VibeVoice)Tests'

SILLIES_TTS_HELPER=/path/to/release/SilliesTTSInference \
  /path/to/release/TTSBenchmark latency vibevoice-realtime-0.5b-8bit STORE_DIRECTORY \
  en 'Hello! I am your little window companion.'
```

Reference fixtures live in `Tests/SilliesWoofSpeechTests/Fixtures/Reference` and
`Tests/SilliesVibeVoiceTests/Fixtures/Reference`. Keep source revisions, manifests, raw transcripts,
measurement logs and test receipts. Disposable reference environments and rejected model weights
can be removed after validation. Local artifacts for this run are under `build/native-tts-integration/`.
