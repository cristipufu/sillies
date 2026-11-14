# Shared transcription boundaries — 14 November 2026

Continuous transcription now uses one boundary implementation and one capture-purpose selection
path across the downloaded providers. `SpeechWindowConfiguration` contains immutable cadence and
qualified continuous-policy values. `SpeechRecognitionContext` resolves purpose and the explicit
qualification override; `WindowSpeechChannel` owns each source's buffer and policy. Providers contain
no copies of calibration, thresholding, window construction, overlap handling or recovery.

Parakeet retains its previously qualified adaptive behavior. Nemotron's streaming adapter uses the same
path. Whisper and Nemotron retain their existing baseline defaults: applying the adaptive gate improved
overall WER but failed the no-regression requirement. New providers default to baseline until qualified. Apple already forwards the complete converted stream to
`SpeechAnalyzer`, with no Sillies energy gate. Talk/dictation keep their established short-utterance
behavior. There is no new setting, migration, microphone permission or background producer.

## Evidence and acceptance

Qualification uses the production native decoders and `DiskSpeechAudioStore`, canonical mono 16 kHz
public research audio, 100 ms input packets and the existing 10 ms analysis frames. Boundary mode is
the only requested difference within each paired comparison. Replay exercises catch-up and final drain;
paced delivery additionally exercises live drafts. The old 600 ms silence interval, 12-second window
cap, 24-second RAM bound and overlap remain unchanged. PCM samples are never amplified by the gate.

Development speech contains eight English and eight Romanian FLEURS recordings, each in original-gain,
RMS-0.0012 quiet and seeded 10 dB additive-noise conditions, plus three no-speech sentinels: 51 pairs.
The final cohort contains 20 new English and 20 new Romanian recordings under the same conditions,
plus three sentinels: 123 pairs. Its per-language text IDs exclude the earlier calibration and holdout
selections; source and executable hashes were frozen before native recognition of this cohort.
Each provider sees the same fixed inputs. This is a small two-language cohort, not evidence for every
supported language or a prediction of error rates in actual calls.

The primary source is [Google FLEURS](https://huggingface.co/datasets/google/fleurs/tree/70bb2e84b976b7e960aa89f1c648e09c59f894dd),
pinned at `70bb2e84b976b7e960aa89f1c648e09c59f894dd`. Source manifests retain original and canonical
checksums and archive members. Supplementary natural speech uses the same ten replies/turns and
continuous ES2002a minute as the [initial qualification](transcription-boundaries-2026-11-14.md), from
the [AMI Meeting Corpus](https://groups.inf.ed.ac.uk/ami/download/). FLEURS and AMI provide this research
audio under CC BY 4.0. No personal recordings or Vault content were used.

The strict raw gate requires fewer errors, a negative upper 95% clustered-bootstrap difference,
no language/condition group increase, no newly lost utterance or watched negation/number, and no new
noise-only words. Small supplementary sets use the regression checks without claiming statistical
improvement. Failed runs remain in the evidence archive.

## Results

| Native comparison | Pairs | Baseline WER | Adaptive WER | Decision |
| --- | ---: | ---: | ---: | --- |
| Parakeet, fresh heldout cohort | 123 | 37.95% | 15.37% | Accepted |
| Nemotron, development | 51 | 31.01% | 13.07% | Passed calibration |
| Nemotron, fresh heldout cohort | 123 | 38.02% | 19.34% | Rejected |
| Whisper, energy-only earlier holdout | 123 | 37.43% | 14.54% | Rejected |

Parakeet's fresh cohort has 2,622 reference words across condition variants. Errors fell from 995 to
403; the paired clustered-bootstrap difference is −22.58 percentage points, with a 95% interval
of **−30.82 to −15.50 points**. Every language/condition group improved or stayed level. All three
noise-only sentinels produced no words. The cohort differs from the initial qualification, so its
absolute WER should not be compared with that report's WER as a temporal model change.

| Parakeet fresh holdout group | Baseline WER | Adaptive WER |
| --- | ---: | ---: |
| English, original gain | 48.09% | 7.42% |
| English, quiet | 31.82% | 5.98% |
| English, noise | 46.65% | 9.33% |
| Romanian, original gain | 15.57% | 15.57% |
| Romanian, quiet | 51.75% | 17.11% |
| Romanian, noise | 34.87% | 34.87% |

Nemotron's heldout aggregate improved substantially, but Romanian clean-speech errors increased from
87 to 89 (19.08% to 19.52% WER), and a quiet Romanian clip lost the negation `nu` that the baseline
retained. Both window and inference inputs differed, so identical-input decoder variability cannot
explain away these failures. The numeric guard additionally flagged “one hundred” becoming “100”;
that particular flag is a known limitation of the conservative token guard, not evidence of a changed
numeric meaning. The genuine negation and subgroup failures independently reject the candidate.
No threshold was relaxed or language-specific routing introduced after seeing these outcomes.
Supplementary rollout checks were stopped for this rejected candidate.

| Parakeet supplementary check | Pairs | Baseline WER | Adaptive WER |
| --- | ---: | ---: | ---: |
| Paced English/Romanian development subset | 6 | 41.90% | 28.57% |
| Automatic-language development subset | 6 | 41.90% | 28.57% |
| Natural meeting replies and turns | 10 | 15.91% | 15.91% |
| Continuous paced meeting minute | 1 | 13.79% | 13.79% |

Every natural excerpt retained its per-clip WER; the continuous minute retained identical text.
Parakeet's fresh holdout sent 30,099,040 baseline samples and 41,744,160 adaptive samples to actual
inference (+38.69%), over 538 and 524 requests respectively. Replay processing totaled 86.09 and
129.04 seconds for 1,384.5 seconds of audio per mode. These are local work/time observations, not
live CPU, battery or performance guarantees. Their purpose is to make the additional decoding cost
visible alongside the quality benefit. Sample counts are direct measurements; wall times were not
taken in an isolated performance run.

## Why Whisper keeps its current default

The energy-only candidate improved development WER from 35.11% to 15.50% in the traced comparison.
Its earlier heldout comparison improved overall WER from 37.43% to 14.54%, but changed the input windows
on a low-noise sentinel and generated additional caption text. That is a genuine gate-attributable
regression under the acceptance rule, so the candidate was rejected.

A second candidate reused the existing native WebRTC classifier and the conversation onset policy
through a per-channel injected classifier factory. It required sustained voice evidence only for
frames newly promoted below the baseline threshold. Stronger-than-baseline frames remained accepted.
A raw-evidence pilot, sustained-onset candidate, and onset-with-turn-hangover candidate were tested.
The final such candidate improved controlled development WER from 34.77% to 26.80% but worsened the
English/noise subgroup. Applying that stronger detector to Parakeet also reduced its already-qualified
quiet-speech gains: development WER was 26.80%, versus 14.40% for the shipped energy policy.
The detector extension and its unused abstractions were removed from production. Its rejected patch,
provenance and raw native outputs are retained. No decoder confidence filter was shipped.

Whisper itself can generate different text for identical input windows. Actual baseline-against-baseline
repeat controls reproduced this on noisy speech and no-speech input. The pinned WhisperKit 1.1.1
[`GreedyTokenSampler`](https://github.com/argmaxinc/argmax-oss-swift/blob/1bbc57cb7fe6410248a685b1c5a3c6d56adc2ed4/Sources/WhisperKit/Core/Text/TokenSampler.swift)
uses random fallback sampling. Production decoding and fallback settings remain unchanged.

The native runner now records optional, typed, bounded traces of window start/count/completion and
actual inference start/count/phase, including retries and excluding cache reuse from inference counts.
Callbacks run outside the input lock and are absent in the app. They contain no PCM, words or tokens
and are separate from the diagnostic archive. The scorer's explicit `boundary-effect` view retains
the raw score and every same-input text variation. Only when both complete ordered traces match
exactly does it use a shared baseline outcome to estimate zero gate effect. Changed windows retain
actual outputs and critical-loss checks; missing or inconsistent traces fail closed. The default raw
gate remains unchanged. This attribution check cannot excuse the low-noise regression above, and does
not establish that the baseline recognizer is free of hallucinations.

## Verification and limits

Regression coverage checks capture-purpose/configuration/override routing through both prepared-model
and direct-streaming construction, per-source calibration isolation, non-finite audio failure,
finalization, inference-cache accounting and reentrant observer cancellation. Scorer tests preserve
raw outcomes, reject incomplete traces and prevent changed retirement boundaries from hiding losses.

Native default checks separately call the normal provider path without boundary overrides, using
public English clips for which explicit baseline recognition made zero inference requests. Two
independent source channels both retain speech with the configured Parakeet default; both remain
silent with the configured Whisper and Nemotron defaults. This checks adapter wiring independently
of the paired runner, whose explicit policy overrides intentionally bypass configured defaults.
The paired comparison and final default checks retain separate source/executable provenance.

The final headless checks passed with mandatory discovered-test completion receipts: **23 focused,
1,235 full, 441 stress and 480 race tests**. No sanitizer findings occurred. The app was rebuilt
locally without launching a visible workflow. Model artifact byte counts and SHA-256 values were
reverified for all three downloaded models.

Apple's file-only native smoke check was attempted, but the system English asset was not available.
Its complete-stream forwarding was verified in source; no Apple quality improvement is claimed.
Visible app, microphone and live-call workflows were not run. No CPU, battery or device-presentation
latency improvement is claimed. More retained audio can require additional native decoding.

Inputs, raw results, frozen source/model/executable hashes, rejected candidates and completion receipts
live in [the evidence archive](data/shared-stt-boundaries-2026-11-14). Audio remains outside Git.
Generated condition/restoration copies are removed after checksum and open-file verification; installed
models and the person's Vault are outside cleanup scope.
