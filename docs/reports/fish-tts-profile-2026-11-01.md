# Fish S2 Pro: measured latency and throughput

This records the baseline investigation before the [follow-up optimizations](voice-optimization-2026-11-01.md).

November 1, 2026. Baseline: [`65aee5f`](https://github.com/cristipufu/sillies/commit/65aee5f64ca85d22a3ce8f31ca35d2d5a4f5dadf), committed and pushed before profiling. [Measurement data](fish-tts-profile-2026-11-01.json) includes every request in the controlled comparison, stage medians, output hashes, and the extracted CPU profile.

**Fish's warm delay is dominated by repeated transformer execution. Cold startup is dominated by verifying the installed files. Sustained generation is also slower than playback on this fixture.** These are three separate problems; reducing the first audio chunk alone will not fix the gaps later in a reply.

This investigation adds opt-in diagnostics, not a speculative inference optimization. The running Sillies app was left untouched. The temporary experiment with a larger GPU command-buffer budget was reverted.

## What was measured

- Apple M4 Pro, 48 GiB RAM, macOS 26.7.2 (25G332), optimized release build. Separate debug measurements establish the development-build penalty.
- Installed `fish-s2-pro-8bit`, revision `c8d4481b3f7cbfe64d855c8b7cda7739502fc3ff`. No downloads; inference runs under a network-denying sandbox.
- Fixed passage: “Hello there. I can start speaking before the whole reply is ready.” The tokenizer produces 34 prompt tokens, including the role/template tokens.
- Seed 123, five requests per helper: request 0 measures first use after preparation; requests 1–4 measure reuse. Ten controlled groups, **50 requests**, produced byte-identical WAV files: SHA-256 `8fd17152090697a935a6081584b4b960a6f4cbb52f1de56bebc4ed9907bfab01` (see the data file for the authoritative hash).
- Each output contains 99 codec frames, 202,752 samples at 44.1 kHz: **4.598 seconds of audio**, delivered in 25 chunks.
- A silent client records actual PCM arrival and acknowledgements. A separate paced sink simulates playback with a 750 ms queue cap. Neither opens an audio device or a visible window.
- All inference commands have a 180-second watchdog. No long-running soak test.

**Latency here means PCM available to the client, not sound presented by a speaker.** This excludes the text model, phrase segmentation, audio-device startup, hardware buffering, echo cancellation, and audible device presentation. The earlier approximately 539 ms Fish observation cannot be equated directly with this fixture's warm PCM time.

“Cold” means a new helper and unloaded runtime, not a reboot or an empty filesystem/Metal cache. No caches were purged. Later groups were thermally nominal; some earlier groups reported fair thermal state. Background load was not eliminated, so all comparisons retain their ranges and outliers.

## Findings that affect the experience

| Measurement | Result | Meaning |
|---|---:|---|
| Final natural warm first PCM, median | **366 ms** | Already-prepared and previously-used runtime |
| Final natural warm generation, median | **5.771 s** | Produces 4.598 s of audio: **1.26× real time** |
| Simulated playback gaps after starting, median | **942 ms** | Starting immediately can exhaust the available audio |
| Final natural preparation | **3.199 s** | Verification, helper launch, tokenizer and runtime setup |
| First request after that preparation | **572 ms** to first PCM | Preparation does not fully execute the model or codec |
| Paced sink waiting | Negligible | Playback backpressure is not slowing this fixture |
| MLX active / process peak allocation | **5.42 / 5.57 GiB** | Tensor allocator figures, not total process RSS |

Repeated natural warm groups generally took about 5.7–6.6 seconds. One early natural request took 9.16 seconds; the unmeasured group also had a 7.31-second request. Those remain in the data. We did not identify the cause of those isolated outliers, and they are not used to assign a precise overhead percentage to the instrumentation.

The unmodified baseline also reproduced the throughput problem: optimized reused requests took **1.27–1.36 seconds per second of generated audio**, versus **2.13** in the debug run. Those earlier runs were unseeded and produced different audio lengths, so their raw durations are not an equal-output A/B test. They establish that development-build speed is materially misleading, and that release optimization alone does not make this fixture real-time.

## Cold preparation: where 3.199 seconds goes

Representative final natural run; these entries partition preparation rather than overlap.

| Segment | Time | What it does and why it costs time |
|---|---:|---|
| Before provider creation | **2,712 ms** | Registry admission and `ModelStore.acquire`; the latter checks paths/sizes and reads every artifact to compute SHA-256. The installed artifacts total about **6.73 GB**. |
| Helper launch, request/response and remaining setup | **18 ms** | Measured remainder after subtracting the provider boundary and engine loading. Not further split into individual OS operations. |
| MLX memory/device initialization | **25 ms** | Applies the helper's existing memory limits; can initialize the Metal allocator/device. |
| Configuration read/validation | **0.25 ms** | Parses and checks the supported architecture. |
| Tokenizer initialization | **400 ms** | Loads the tokenizer files and constructs its processing machinery. |
| Tokenizer compatibility validation | **1.57 ms** | Confirms EOS and semantic-token IDs. |
| Speech tensor descriptors | **2.81 ms** | Parses safetensors metadata and creates lazy tensor loads. |
| Generator setup | **37.88 ms** | Creates transformers and materializes the restricted semantic output-head rows. |
| Codec tensor descriptors | **1.06 ms** | Parses codec metadata; only decoder-relevant tensors are retained. |
| Other engine setup | **0.83 ms** | Filtering and object setup outside the individual stage timers. |

The provider boundary independently isolates the large pre-helper cost. Repeating **only** `store.acquire` after inference took **2.890 seconds**. The next run measured 2.868 seconds before the provider and 2.859 seconds for the isolated verification replay. Source inspection confirms full-file SHA-256 reads in [`ModelFiles.verify`](../../Sources/SilliesModelStore/ModelFiles.swift).

This verification is deliberate integrity work, not model inference or downloading. It happens on a new residency/lease, not on every request while the registry retains the loaded model. Any optimization must preserve detection of replaced or modified artifacts; deleting the checks is not an acceptable speed fix.

The small `loadArrays` times do **not** mean gigabytes of model data are loaded in milliseconds. The checked-out MLX safetensors loader constructs lazy `Load` primitives. First evaluation pays deferred weight materialization and kernel/setup costs. In the unmodified release baseline, first PCM from a new runtime ranged from 4.76 to 10.72 seconds, including preparation; the largest first-ever run was not reproduced as a controlled cold-cache experiment.

## Warm synthesis: every stage

MLX is lazy. A timer around graph construction does not include the work that a later `eval` triggers. Two complementary modes were used:

- **Natural:** keep the existing evaluation boundaries; measure actual scheduling behavior.
- **Fenced:** evaluate tensor outputs at stage boundaries to attribute deferred work. This adds synchronization and can change performance; its numbers are not pure GPU kernel time.

The final natural group took 5.771 seconds at the median; its fenced counterpart took 6.057 seconds. The unmeasured group took 6.103 seconds, while a repeated natural group took 5.822 seconds. This variability prevents a clean estimate of the small clock/reporting overhead; the extra fences are an attribution probe, not an optimized execution path.

The table uses medians of the final four warm requests in each mode. All times are milliseconds for the **whole 4.598-second output**. Independent medians do not sum exactly to the median request.

| Stage | Calls | Natural | Fenced | Explanation |
|---|---:|---:|---:|---|
| Prompt tokenization | 1 | 80.5 | 80.8 | Seven role/content segments go through the tokenizer; includes its regex processing. |
| Prompt prefill | 1 | 1.1 | 82.1 | Runs the 34-token prompt through the main transformer. Natural mode defers most execution into semantic sampling. |
| Semantic output projection | 100 | 0.9 | 19.9 | Projects hidden state to the permitted semantic tokens plus EOS. |
| Semantic sampling | 100 | 115.0 | 29.9 | Sort/filter, temperature/probability selection, random draw and CPU result read; natural timing includes pending prefill/projection. |
| Semantic repeat recovery | 21 | 4.9 | 4.9 | Existing alternate sampling when a semantic code repeats; not additional language-model generation. |
| Fast-transformer prefill | 99 | 236.8 | 239.0 | Resets and seeds its cache from the main hidden state for each audio frame. |
| Fast residual forward passes | 891 | 120.3 | **2,155.2** | Nine sequential residual-code predictions for every frame. Natural timing largely measures graph construction. |
| Residual output projections | 891 | 1.1 | 165.0 | Projects each residual hidden state to the codec vocabulary. |
| Residual sampling | 891 | **2,149.0** | 215.0 | Selects and reads the residual code. Natural mode also executes the preceding forward/projection graph. |
| Next-frame embeddings | 99 | 5.5 | 42.2 | Combines semantic and codebook embeddings for the next main-transformer step. |
| Main-transformer next-frame step | 99 | **2,094.0** | **2,071.9** | Advances the main autoregressive state. Natural breakdown: **111 ms graph construction + 1,983 ms evaluation**. |
| Waveform codec, inclusive | 25 | **857.4** | **880.3** | Converts the code frames to PCM; breakdown below. |
| PCM delivery and acknowledgement | 25 | 82.5 | 81.6 | Validates/encodes PCM, transfers it through the local pipes, awaits the client sink and acknowledgement. |

Approximate fenced shares: **46% residual generation, 35% main-transformer advancement/embeddings, 15% waveform decoding**, with prompt work, semantic selection and transport accounting for the remainder.

The misleading result would have been “sampling wastes 2.15 seconds.” Fencing shows most of that interval is pending neural-network execution. Isolated residual sampling is about 215 ms, roughly 3.6% of the request. Removing CPU scalar reads cannot reasonably be credited with the entire 2.15 seconds without an experiment.

### Why the “fast” transformer is expensive

The implementation is in [`FishCodeGenerator`](../../Sources/SilliesFishSpeech/FishCodeGenerator.swift) and [`FishTransformer`](../../Sources/SilliesFishSpeech/FishTransformer.swift). The main transformer has 36 layers. The fast transformer has four, but executes once to initialize each frame and then nine more times to predict its residual codes. That is approximately **40 fast-layer passes versus 36 main-layer passes per frame**, with sequential dependencies between predictions. “Fast” describes the smaller model, not its aggregate share of this implementation's runtime.

This fixture performs 891 residual predictions, not one neural-network call per spoken sentence. Each frame represents only 2,048 / 44,100 = **46.44 ms** of sound. The current chunk size waits for four frames, or **185.76 ms of audio**, before decoding and delivering it.

### First chunk

In the earlier fenced group, the first PCM chunk took approximately 380 ms. Its component medians were approximately:

| Work before first PCM | Time |
|---|---:|
| Tokenization | 81 ms |
| Prompt prefill | 81 ms |
| Four fast-prefill/residual-prediction sequences | 114 ms |
| Three main-transformer advances and embeddings | 63 ms |
| First waveform decode | 37 ms |
| Semantic selection, bookkeeping and delivery | Remaining few milliseconds |

This explains the warm startup floor without attributing it to leading silence. The measured output had no leading samples below the diagnostic's 0.001 amplitude threshold. That threshold is a signal check, not a perceptual audibility measurement.

Reducing frames per chunk could reduce time to the first chunk, but would increase codec calls and would not fix slower-than-real-time generation. It needs a separate latency/throughput experiment.

## Waveform codec breakdown

These rows are **inside** the 880 ms fenced codec total, not additional work. The codec maintains causal history so chunks join continuously.

| Codec segment | Fenced time | Explanation |
|---|---:|---|
| Codebook lookup/projections | 10.4 ms | Looks up and combines the ten codes per frame. |
| Codec attention | 130.0 ms | Applies the post-quantizer transformer with retained keys/values. |
| First latent upsample | 24.1 ms | Doubles the latent sequence and applies its convolutional block. |
| Second latent upsample | 19.6 ms | Doubles it again. |
| Decoder input convolution | 51.1 ms | Projects the latent channels into the waveform decoder. |
| Decoder block 1, ×8 | 198.6 ms | Upsample, nonlinearities and three dilated residual units. |
| Decoder block 2, ×8 | 184.9 ms | Same family of operations at the next resolution/channel count. |
| Decoder block 3, ×4 | 149.4 ms | Further waveform reconstruction. |
| Decoder block 4, ×2 | 99.3 ms | Final upsampling block. |
| Output activation/convolution/CPU array | 12.7 ms | Produces bounded float PCM and materializes it for transport. |

There are **500 convolution-history evaluations** and **200 attention-history evaluations** across the 25 chunks. Their inclusive timers total about **562 ms** and **110 ms**, respectively. Those are execution boundaries that also materialize upstream work, **not** proof that copying history alone wastes 672 ms. They are worthwhile targets for a controlled evaluation-scheduling experiment, while preserving bounded caches and causal equivalence.

Codec-kernel normalization is cached. The `codecKernelPreparation` stage ran 44 times and took 43 ms in the final natural first request (40 ms fenced), then disappeared on reused requests; it is not recurring warm cost.

## CPU evidence and the GPU-budget experiment

A 15-second Time Profiler capture attached only to the helper. It contained 9,569 usable weighted stack samples, with 172 additional rows lacking a usable backtrace excluded. Relevant observations:

| CPU stack observation | Share of usable weighted samples | Interpretation |
|---|---:|---|
| `mlx::core::eval` present in stack | 41.2% | Evaluation includes scheduling, dispatch and synchronization as well as preparation of GPU work. |
| Metal command-queue submission present | 26.8% | Submitting command buffers is substantial CPU activity, including work on Metal's other threads. |
| `iokit_user_client_trap` leaf | 19.6% | Frequent driver/kernel interaction. |
| `_xzm_free` leaf | 4.0% | Allocation lifetime management contributes some CPU work. |
| ICU regex matcher leaf | 2.1% | Consistent with the separately measured tokenizer cost. |

These sample percentages overlap for inclusive stacks and do not partition elapsed time. They cannot establish GPU occupancy, memory bandwidth saturation, or a precise avoidable driver cost.

To test a concrete hypothesis, a separate helper changed only `maximumGPUOperationsPerBuffer` from 8 to 32. Everything else, including seed and audio, remained identical:

| Experiment order | Warm total median | First PCM median |
|---|---:|---:|
| 32 operations, first run | 5.960 s | 375 ms |
| 8 operations, repeated baseline | 5.727 s | 365 ms |
| 32 operations, repeated run | 5.743 s | 363 ms |

All three groups were thermally nominal. **No repeatable throughput improvement was demonstrated.** The first 32-operation group was slower; the repeat was essentially equal to the baseline. The production budget remains eight. There is no evidence here to trade away compositor fairness by raising it.

Metal System Trace was attempted twice, with 15-second and 5-second capture windows. Both stopped collecting but failed to finish saving within a 60-second watchdog. They provide **no usable per-kernel GPU timings**. This report therefore does not claim to distinguish GPU arithmetic, memory bandwidth, and driver stalls within the measured evaluation intervals. Raw Instruments metadata was discarded; the repository contains only extracted numerical results.

## What to improve, in priority order

1. **Reduce repeated cold verification while retaining integrity guarantees.** The measured 2.7–2.9 seconds is a substantial and well-isolated startup cost. Keep verified residency alive for the conversation, as the registry already supports. Investigate a safely invalidated verification cache tied to file identity/metadata or immutable installed artifacts before changing `ModelStore.acquire`. This helps all large local-model providers, not only Fish.
2. **Optimize residual and main-transformer evaluation with equal-output experiments.** Together they dominate warm work. Candidates include compiling/fusing compatible evaluation regions, reducing synchronization, and keeping residual-code dependencies on the GPU. Require measured improvements, cancellation, bounded memory, unchanged generation semantics and UI fairness; the current data does not prove any particular implementation will win.
3. **Evaluate codec synchronization as a separate change.** Its 700 history-evaluation boundaries are measurable, but much of their time is real upstream computation. Compare a bounded batched evaluation strategy against the existing causal-reference tests and identical streamed PCM.
4. **Reduce prompt processing overhead.** Approximately 81 ms matters for a 366 ms first chunk. Cache immutable template token segments or investigate tokenizer-call overhead, with exact token-equivalence tests. Do not concatenate template segments blindly: that can alter token boundaries.
5. **Tune first-chunk policy after throughput work.** Compare smaller initial chunks against sustained generation rate and codec overhead. More startup buffering can hide some gaps but increases latency; it does not make the model faster.
6. **Treat transport as a smaller opportunity.** About 82 ms per full request is measurable, but it is only around 1.4%. Playback waiting was negligible, and waveform-to-CPU conversion was already included in the small codec output stage.

No claim is made that all transformer time is unavoidable model cost. It contains our execution strategy and MLX/Metal overhead too. Conversely, a CPU stack in a driver or a timer at `eval` does not justify labeling its whole duration as removable waste.

## Reproduce without disturbing the running app

Build to a separate location, using an already-installed model store:

```sh
source scripts/toolchain.sh
make build BUILD_DIR=/tmp/sillies-fish-profile
profile_bin="$(swift build -c release --show-bin-path)/TTSBenchmark"
profile_output="$PWD/build/fish-profile-new"
mkdir -p "$profile_output"

env \
  SILLIES_TTS_HELPER=/tmp/sillies-fish-profile/Sillies.app/Contents/Helpers/SilliesTTSInference.app/Contents/MacOS/SilliesTTSInference \
  SILLIES_FISH_PROFILE_DIRECTORY="$profile_output/helper" \
  SILLIES_VOICE_PROFILE_DIRECTORY="$profile_output" \
  SILLIES_FISH_PROFILE_MODE=natural \
  SILLIES_FISH_PROFILE_SEED=123 \
  python3 scripts/run-bounded-test.py 180 \
  /usr/bin/sandbox-exec -p '(version 1)(allow default)(deny network*)' \
  "$profile_bin" profile fish-s2-pro-8bit /path/to/installed/model-store en \
  'Hello there. I can start speaking before the whole reply is ready.'
```

Use a fresh output directory for each run. Repeat with `SILLIES_FISH_PROFILE_MODE=unmeasured` for deterministic synthesis without per-stage synthesis clocks, or `fenced` for attribution. Use `SILLIES_VOICE_PROFILE_DELIVERY=paced` for the silent playback-rate simulation. Do not run builds, tests, other inference benchmarks or Instruments captures concurrently with timing comparisons.

The tool writes `client.json`, five WAV files, and helper stage JSON. Profiling is disabled unless explicitly configured. Reports retain bounded stage samples, add no timers or network services, and stay within the helper's ownership boundary. Seeds and extra evaluation fences apply only to diagnostic runs. Ordinary synthesis keeps its sampling and existing evaluation behavior.

The first five-run sequence includes preparation, first use and four reused requests. It then repeats installation acquisition separately to measure verification; that replay is not part of synthesis timing. Timings include helper report serialization before the final completion response, but individual stage timers do not include writing the report.

## Coverage and limits

- Release baseline, controlled natural/fenced/unmeasured comparisons, paced delivery, isolated verification replay, CPU sampling and the 8-versus-32 experiment are complete.
- All 50 controlled outputs match byte-for-byte. This establishes equivalence for this fixture, not all text, languages, voices or sequence lengths.
- Memory figures were stable across the warm fixture. Peak memory is cumulative within each helper; this is not a general leak or memory-pressure test.
- Final `make check BUILD_DIR=/tmp/sillies-fish-profile-check` passed with the repository Xcode toolchain: 534 receipt-verified headless tests, lint, architecture checks, localization extraction, signed debug build, helper GPU self-tests, parent-exit checks, and catalog validation. The focused Fish/transcript run also passed all 12 selected tests. An initial full run exceeded the existing transcript-publication timing budget; the isolated test and subsequent full runs passed without changing its threshold.
- No visible GUI checks, device-presentation latency measurement, long-input scaling study, other Mac benchmark, or usable GPU kernel trace was obtained. Those limits remain explicit rather than inferred from these measurements.
