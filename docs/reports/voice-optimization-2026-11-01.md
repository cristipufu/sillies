# Local model and voice optimizations

Follow-up to the [Fish profiling report](fish-tts-profile-2026-11-01.md). [Measurement data](voice-optimization-2026-11-01.json) retains individual requests, output hashes, memory readings and stage medians, including outliers and the later contended runs.

## Final paired results

After build/test jobs finished, both final comparison groups reported nominal thermal state and produced the same waveform. Each row is the median of four reused requests; the first request in each helper is excluded as warm-up.

| Metric | Baseline | Final implementation |
|---|---:|---:|
| First PCM | 357 ms | **268 ms** |
| Full generation, 4.598 seconds of audio | 5.567 s | **5.270 s** |
| Waveform codec | 835 ms | **727 ms** |
| Prompt tokenization | 80.19 ms | **0.22 ms** |
| Simulated playback gaps after immediate start | 748 ms | **545 ms** |

That is approximately 25% less startup latency, 5.3% less total generation time, and 13% less codec time in this comparison. Both groups used the updated benchmark client's verification cache; the helper runtime is what differs. The separate pre-change acquisition measurements establish the verification improvement. These results describe this fixture on this Mac, not a hardware-independent guarantee.

## Shared model verification

The optimization belongs in `ModelStore`, which is used by the text/LLM, STT/diarization and TTS registries. Providers do not implement their own cache or bypass verification.

`ModelArtifactVerifier` now keeps bounded, process-local evidence of successful SHA-256 checks. A hit requires the expected checksum and the opened file's device, inode, generation, size, mode, modification time, change time and creation time to match. Change times include nanoseconds; coarse timestamps fall back to hashing. The expected checksum is part of the cache key, so a different manifest cannot reuse an unrelated check.

Descriptor access is isolated in the focused `SilliesFileSystem` target. It opens regular files without following a final symbolic link, prevents a substituted FIFO from blocking open, bounds read buffers, closes descriptors reliably and asserts worker execution. The model store retains policy and cancellation ownership. Architecture checks keep native filesystem imports out of the store and prevent UI dependencies in the new target.

After hashing, the verifier checks both the open descriptor and the current pathname again. Files changed or replaced during verification are rejected. Failed checks never enter the cache. The cache holds at most 4,096 entries and is never serialized or trusted from an installation receipt.

Downloads are verified inside their unpublished staging directory. Publishing that directory preserves the file evidence, so first activation can reuse the check that just completed during installation. Corrupt or cancelled staging data never becomes an installed model.

Measured unchanged Fish acquisition went from **2.86–2.89 seconds to roughly 1.5–2.3 ms**. The offline checks also exercised the shared path with Kokoro, Pocket and Qwen; metadata checks over their larger artifact lists took approximately 14–24 ms. These are acquisition measurements, not complete provider startup times.

**The first verification after restarting the app still reads the files fully.** The cache helps activation after installation, reacquisition after eviction, and switching away from and back to an unchanged model during the same app lifetime. It does not replace byte verification with a persistent “already checked” flag.

## Fish synthesis

Three focused changes preserve the existing model, precision, sampling and audio:

1. `FishPrompt` caches only the six fixed template segments when the runtime loads. The content segment still goes through the original tokenizer, and every segment boundary remains unchanged. Warm prompt processing fell from about **81 ms to 0.23 ms** on the fixed fixture. This moves fixed work to preparation; it does not cache user text.
2. Codec history is materialized at the end of each audio chunk. The streaming convolution and attention owners still retain bounded causal state, but history evaluations drop from **700 to 50** for the 25-chunk fixture. The decoder still evaluates its waveform blocks and checks cancellation. Codec time improved from approximately **857 ms to 745–761 ms** in the early paired runs. Peak MLX allocation increased by about **99 MiB**, then stayed stable across reuse; active allocation stayed approximately 5.42 GiB.
3. Rotary pair math uses MLX compilation for the repeated one-token decode shape. Variable-length prompt and codec chunks keep the ordinary path, avoiding specialized compiled graphs for every utterance length. The compiled function is owned by the transformer instance and captures no mutable inference state. An independent CPU pair reference confirms the required bfloat16 rounding across offsets and lengths. The fixed eight-operation Metal command-buffer budget remains unchanged.

The first prompt/codec comparison measured first PCM improving from **369 ms to 283 ms**, with total generation improving from **5.90 s to 5.70 s** for the same 4.60-second waveform. An additional rotary-only comparison measured **5.54 s versus 5.30 s**; its earlier run was noisier and did not establish a gain by itself. The final bounded-shape implementation was also checked against the original runtime using both an English fixture and a French/English fixture: outputs matched byte-for-byte.

These are PCM timings, not speaker-presentation latency. Fish remains slower than real time on the original fixture; startup gains do not eliminate every potential playback underrun. There is no claim of a universal percentage improvement on other Macs or all passages.

## Other providers and measurement limits

Kokoro, Pocket and Qwen each completed five silent, network-blocked synthesis requests through the updated shared store. Their provider algorithms were not rewritten. These runs validate the integration and expose their current behavior; they are not equal-output before/after speed claims.

The Kokoro fixture had about 287 ms of generated low-level lead-in before the diagnostic's 0.001 signal threshold, even though PCM was ready quickly. That is distinct from model execution time. No amplitude-based trimming was added: changing waveform onset requires separate validation that quiet speech and consonants remain intact.

An intermediate final-build run overlapped with another development test suite and heavy system indexing. The evidence retains that run, whose Fish requests reached 7.5–10.5 seconds. It is excluded from clean speed comparisons because the workload was not controlled. Output equivalence still held. Individual GPU kernel timings remain unavailable because Instruments failed to save its Metal captures within the watchdog; evaluation timers include scheduling and synchronization.

## Validation

- `make check BUILD_DIR=/tmp/sillies-voice-opt-check` passed: **542 receipt-verified headless tests**, lint, architecture boundaries, localization extraction, signed debug build, inference helper GPU self-tests, parent-exit checks and catalog validation.
- The architecture checker passed **82 regression fixtures**, including the new filesystem and verifier boundaries.
- The focused store/Fish run passed **40 tests**. New regressions cover unchanged-file reuse, post-install reuse, same-size corruption with restored modification time, changed manifest checksums, inode replacement, changes during hashing, symbolic links, wrong sizes and cancellation on a cache hit. A fresh verifier always hashes again.
- Streaming convolution, upsampling and attention tests exercise the new chunk-end history materialization against independent causal references. The rotary test checks compiled and ordinary paths without treating them as interchangeable approximations.
- Fixed-seed English and mixed-language output hashes match the baseline. Benchmarks are bounded and silent; no multi-hour soak or visible GUI test was run.
- The running app was not restarted or replaced. The release artifact is `/tmp/sillies-voice-opt-final/Sillies.app`.
