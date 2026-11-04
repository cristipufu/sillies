# Spoken-turn optimization investigation — 4 November 2026

Baseline: `30d4ae9678d1bef06a320745931d1c0edb196699`. Apple M4 Pro, 48 GiB RAM,
macOS 26.7.2 (25G332), Swift 6.4.2. Native timing uses optimized release helpers.
All inputs are synthetic or prerecorded; sinks and tests are headless. The running app,
microphone, personal conversations and model selections were left untouched. No models were downloaded.

## Retained product changes

**Presentation no longer stalls inference or speech.** Previously, `ChatTurnStream.append` awaited
the renderer before enqueueing a ready phrase; the text helper also waited for that callback before
receiving its next acknowledgement. A busy UI could therefore stall both branches.
`ChatTextPresentation` now owns one delivery task and one replaceable pending snapshot. Ready speech
is enqueued first, token delivery can continue, and finishing joins the final presentation before
committing the reply. Failure/cancellation stops native speech before waiting for the renderer.
The unchanged phrase limits, 350 ms opening deadline and per-turn text bounds still apply.

The blocked-renderer regression failed on the baseline. It now passes, alongside a 1,000-update
coalescing test, final-delivery ownership and cancellation while presentation is suspended. These
are deterministic ordering/bounded-work checks, not measurements of compositor frames or a claim
that normal unblocked rendering was adding a particular number of milliseconds.

**Fish materializes one audio frame instead of every residual token.** Nine codebook choices remain
on the GPU until the codec needs the complete frame. Prefill builds the retained attention state
without evaluating an unused final layer output. Sampling, precision, weights, chunk size, codec,
and the eight-operation GPU command-buffer budget are unchanged. Cancellation remains checked while
building each step and immediately after evaluating the frame; caches still reset on every exit.

| Fixed fixture | Warm first PCM, baseline → final | Whole synthesis, baseline → final | Simulated playback gaps, baseline → final |
| --- | ---: | ---: | ---: |
| English, 4.598 s of audio, seed 123 | 265.7 → 257.8 ms | 5.228 → 5.012 s | 503.6 → 305.9 ms |
| French/English, seed 29 | 269.4 → 257.6 ms | 6.329 → 6.050 s | 670.2 → 413.4 ms |

Each entry is the median of four warm requests, following a separately retained first request.
Order is baseline/final for English and final/baseline for the second passage. **All original
Float32 samples match exactly** in ten paired outputs; this is stronger than comparing quantized WAVs.
Peak MLX allocation stays around 5.66 GiB, with differences of only a few kilobytes in the final pairs.
All final paired requests reported nominal thermal state. This is approximately 4.1–4.4% less
generation time on these fixtures. Fish still takes longer than playback, so remaining gaps are real.
PCM arrival and simulated queue gaps are not audible-device latency.

## Speech and other voice providers

Parakeet Ultra and Nemotron Unified each transcribed three prerecorded inputs, including inserted
300 ms and 650 ms pauses. Both retained the requested address and time; punctuation/number formatting
differed. Parakeet finalization took 55–75 ms; Nemotron took 25–42 ms. Native channel reuse remained
effective. These short English checks do not establish multilingual recognition accuracy or natural
conversational endpoint accuracy. The required Apple speech assets were absent, and Whisper weights
were unavailable in the test stores. Those paths receive no new native speed claim.

| Voice provider | Warm first PCM | Warm synthesis | Generated audio |
| --- | ---: | ---: | ---: |
| Kokoro | 72 ms | 112 ms | 4.35 s |
| Pocket TTS | 42 ms | 669 ms | 3.36 s |
| Qwen3-TTS 0.6B | 66 ms | 3.683 s | 5.88 s |

These are current controls, not before/after gains. The 1.7B Qwen voice pack was not tested. Kokoro's
waveform still contains roughly 287 ms before the diagnostic signal threshold; quiet samples were
preserved. Pocket and Qwen can generate different waveforms across requests, so their durations are
not equal-output comparisons. All four voice families passed actual worker cancellation and recovery:
joining cancellation took approximately 10–57 ms, and the next utterance produced valid audio.

## Concurrent text and voice generation

The final probe ran with network access blocked and matching release helpers. Each model pair has
one cold observation followed by sequential/overlapping/overlapping/sequential observations. The
table shows warm medians, two observations per schedule. First PCM is measured from the start of
the text request, including the wait before synthesis is admitted.

| Text model + voice | First PCM, sequential → overlapping | Simulated gaps, sequential → overlapping |
| --- | ---: | ---: |
| Qwen 3.5 4B + Fish | 1.225 → 0.508 s | 297 → 713 ms |
| Qwen 3.5 4B + Kokoro | 1.060 → 0.230 s | 0 → 0 ms |
| Qwen 3.5 4B + Pocket | 1.040 → 0.197 s | 0 → 0 ms |
| Qwen 3.5 4B + Qwen3-TTS 0.6B | 1.072 → 0.221 s | 34 → 40 ms |
| LFM 2.5 24B + Fish | 6.668 → 5.345 s | 308 → 519 ms |
| Gemma 4 26B + Fish | 1.833 → 0.504 s | 285 → 534 ms |
| Gemma 4 12B + Fish | 2.386 → 0.720 s | 367 → 1,375 ms |

Generated text matched across all five observations within each pair. Fish and Kokoro PCM matched
exactly; Pocket and Qwen voice outputs varied, so those rows are descriptive observations rather
than equal-output speed comparisons. The earlier start does not remove Fish's throughput limit:
simultaneous GPU work increased its playback gaps. This supports retaining the existing admission
policy instead of forcing overlap for every pairing.

## Decisions without a product policy change

- **Turn ending:** keep 900 ms of silence. The prerecorded ASR checks do not supply natural
  end-of-turn labels. Reducing the threshold would change which pauses interrupt a user; there is
  no evidence here to justify that tradeoff.
- **STT cadence/finalization:** retain per-engine cadence and flush semantics. Complete-window
  draft reuse is already implemented; native finalization was short on the available models.
- **Phrase segmentation:** retain the current word/clause boundaries. The shared renderer wait was
  removable without altering pronunciation or prosody; smaller phrases would need new quality evidence.
- **Text/voice overlap:** retain the current admission policy. The contention probe finds earlier PCM
  but more Fish underruns under simultaneous GPU work. That does not establish one better policy for
  every model pair or Mac. No memory thresholds or GPU budgets were relaxed.
- **LLM retrieval/prompt policy:** leave profiles and prompts unchanged. Archive preparation already
  uses a bounded recent page/checkpoint, and semantic memory queries have a bounded deadline. The
  previous memory/evidence experiments did not qualify a broad prompt replacement. This investigation
  improves the shared streaming handoff; it does not claim higher reasoning or tool-use scores.

## Measurement review and reproducibility

Original PCM hashing was added before the final Fish comparisons. A known Float32 sample vector,
different chunk boundaries and a sub-Int16 change independently exercise the hashing implementation.
The overlap probe uses one monotonic origin for text and audio, validates streamed/final text, records
request admission separately, and captures audio completion before waiting for its peer. It excludes
WAV writing from execution time. These self-checks now run in `make check`.

The initial overlap launches used an older packaged text helper and failed before producing text.
Rebuilding the helper from current sources resolved them; failed attempts remain in the evidence.
The first preliminary Fish baseline overlapped a compilation and is excluded from the final comparison.
Subsequent paired measurements ran without concurrent build/test jobs. No output, timeout or failure
was repaired with an answer filter or removed from a score: this investigation has no task score.

The contention probe deliberately speaks a fixed passage while a text model generates a separate
fixed task. It uses the production registries, provider adapters, memory admission and a paced silent
sink. It is **not the complete Chat pipeline**, does not use its phrase assembler, and does not measure
speaker presentation. The main chat leaderboard is unchanged.

Two Fish candidates were tested: deferring residual-token materialization, then also removing the
unused prefill evaluation. The first gave roughly 2% lower synthesis time in the preliminary English
comparison; the final implementation gave the gains above. No further native tuning was attempted.
The execution ledgers account for 851.4 seconds. Four initial groups lack outer elapsed-time receipts;
their individual 120-second watchdogs give an additional upper bound of 480 seconds. This remains
within the 1,800-second model-experiment budget; compilation and ordinary tests are separate.

Evidence is retained under [data/spoken-turn-2026-11-04](data/spoken-turn-2026-11-04/):

- [Final measurements](data/spoken-turn-2026-11-04/results.json.gz): all 20 paired PCM requests and
  all 35 final contention observations, including the separate cold requests.
- [Raw evidence](data/spoken-turn-2026-11-04/raw-evidence.json.gz): provider stages, preliminary and
  failed attempts, STT/cancellation logs, commands, execution ledgers, model revisions, executable
  hashes and generated WAV hashes.
- [Source overlay](data/spoken-turn-2026-11-04/source-overlay.json.gz): modified/new code over the
  baseline commit, plus the dependency lockfile.
- [Speech fixtures](data/spoken-turn-2026-11-04/speech-fixtures.json.gz): the three exact prerecorded
  ASR inputs as base64 WAVs and their expected words. No personal audio is included.
- [Verification](data/spoken-turn-2026-11-04/verification.json.gz): regression, full-check and sanitizer
  logs, with discovered-test inventories and completion receipts. The deliberately failing
  baseline regression is retained separately from passing implementation checks.

[SHA-256 checksums](data/spoken-turn-2026-11-04/SHA256SUMS.json) cover the five evidence archives
and the independent audit source.

The independent [audit](data/spoken-turn-2026-11-04/audit.py) verifies counts, finite ordered timing,
recomputes playback gaps, checks equal-output comparisons and rejects deliberately broken receipts.
Run it without models or inference:

```sh
python3 -B docs/reports/data/spoken-turn-2026-11-04/audit.py
```

Native reproduction uses the release `TTSBenchmark profile`, `overlap`, and `recovery` commands
documented in the [voice contribution guide](../contributing/voice-models.md), with the fixed inputs,
seeds and environments in the execution ledgers. Use the baseline helper only for baseline arms;
keep the final measurement runner for both sides so original PCM hashing and timing semantics match.

## Validation

- Final `make check`: 753 selected tests completed across 19 runs, plus architecture/format checks,
  localization, benchmark self-checks, signed-helper self-tests, parent-exit checks and catalog validation.
- Final `make race-check`: 211 selected tests completed across 14 runs with no Thread Sanitizer
  race reports. This includes all four new presentation/coalescing/cancellation regressions.
  MLX tensor code is excluded from TSAN by its runtime restriction; Fish's seeded equivalence checks
  run in ordinary tests and its real helper was exercised by the paired native measurements.
- The independent measurement audit passed all 20 final PCM requests and 35 contention observations.
  Source-overlay contents and archive checksums were verified against the tested working tree.
- Native voice cancellation/recovery passed for Fish, Kokoro, Pocket and Qwen3-TTS 0.6B.

All verification was headless. Visible GUI/compositor tests, actual speaker presentation,
microphone endpoint accuracy and broader multilingual recognition quality were not measured here.

## Questions and acceptance criteria

1. Locate delay between speech ending, recognition finalizing, useful text, a speakable phrase,
   first PCM and device presentation. Preserve the distinction between actual measurements,
   synthetic timing controls and simulated playback.
2. Investigate Fish's per-codebook CPU synchronization. Compare unchanged weights, sampling,
   seed, text and audio output; accept only identical PCM with a repeatable latency or throughput
   improvement. Check bounded memory and cancellation as well as total generation time.
3. Check recognition finalization and turn boundaries across the installed speech providers.
   Do not reduce silence thresholds or skip native flushing without pause/accuracy evidence.
4. Check phrase delivery and model admission for avoidable waits shared by voice providers.
   Do not trade lower first-PCM timing for missing words, degraded phrasing or playback gaps.
5. Review text/voice overlap and remaining retrieval work. Keep per-model decisions separate
   from the shared algorithms. Do not change prompt policy based on timing alone.

The plan was recorded before native experiments. Use at most two implementation candidates per
mechanism before stopping without a justified gain.
Native experiments have individual process watchdogs and an aggregate 1,800-second execution
budget, excluding compilation and ordinary tests. Preserve failed/interrupted runs. Compare warm
requests separately from preparation; repeat promising paired comparisons in reversed order.
Do not combine stage medians into an invented end-to-end latency, or update the full chat
leaderboard from these targeted checks.

## Research

- [MLX lazy evaluation](https://github.com/ml-explore/mlx/blob/main/docs/src/usage/lazy_evaluation.rst):
  scalar extraction forces evaluation. An evaluation boundary can include earlier deferred work;
  timing graph construction alone cannot attribute GPU execution.
- Prior [voice optimization](voice-optimization-2026-11-01.md) and
  [provider validation](provider-optimization-2026-11-01.md) already cover verification caching,
  prepared voices, unchanged final STT results, tokenization and early device preparation.
  These are the starting implementation, not new gains in this investigation.
