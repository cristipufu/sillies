# Nemotron transcription recovery — 14 November 2026

Nemotron continuous transcription now uses adaptive boundaries with bounded signal normalization and
native streaming continuity. On a fresh English/Romanian cohort, WER fell from **34.65% to 11.80%**
against the shipped `471931c` executable. Every language/condition group improved, with no newly lost
watched negation/number, whole utterance or additional noise-only words. This is evidence for the
specified public recordings and conditions, not a guarantee of accuracy in every meeting.

## Root causes and implementation

The original quiet Romanian negation was already wrong in native decoder results before Sillies
formatted or committed the transcript. Replaying identical windows at different gains isolated an
amplitude-dependent recognition error. A twofold gain recovered the negation and retained a separate
time-range control; fourfold and larger gains lost that time range. The final policy therefore caps
amplification at **2× (+6 dB)** and uses a peak ceiling of **0.125**. Already healthy samples are not
attenuated or amplified. A source's highest observed peak can lower gain but quiet gaps cannot raise
it again. A fresh source resets the policy. The AAC recording, speaker analysis and playback receive
the original audio; only decoder input is adjusted.

`SpeechSignalGain` is a pure Core policy. `SpeechSignalNormalization` validates samples and supplies an
immutable adjustment. `SpeechIncrementalWindow` includes gain in input identity, so a changed gain
replays retained audio instead of mixing differently scaled prefixes in native state. Invalid samples
and positions fail recoverably before native calls; conversion and sample-position addition are checked.

The second loss occurred at a 12-second window rollover. The first native window had correctly decoded
words which Sillies deferred for overlap reconciliation. Reinitializing the recurrent decoder on a short
replay could return nothing or change a negation. Replaying more context fixed one example but still
changed other words. The accepted implementation separates a logical **window boundary** from an
**utterance ending**: ordinary window cuts preserve native decoder state and append only unseen samples;
utterance endings flush it. Native word positions are mapped back into the current window. Continuous
word clocks use one-sample rounding tolerance and do not apply the word-replacement heuristic used for
independently decoded windows. Regression tests preserve both short and repeated words at these seams.

Native transcript/token histories have a fixed **60-second episode bound**, independent of recording
length. At a required restart, the window retains the encoder's configured **5.6-second left context**.
That duration is derived from `NemotronRecognitionConfiguration`, the same owner that creates the
native encoder configuration. The [model card](https://huggingface.co/nvidia/nemotron-labs-unified-asr-0.6b)
describes the supported buffered streaming contexts; weights and the 70/7/7 configuration are unchanged.
No native runtime expires independently of its app-owned registry lifetime.

`SpeechWindowConfiguration` carries the bounded replay duration through the common window channel.
The 12-second input window, 24-second audio memory bound, 64 MiB backing-store limit, pause interval
and capture permissions remain unchanged. Every boundary retires audio even when recognized words
precede replay context. Invalid replay durations fail before a worker starts.

Native model ownership and PCM/token conversion belong to `NemotronNativeDecoder`. The engine owns
normalization, sample identity and recovery through the injected `NemotronDecoding` contract. Failed
or cancelled native work invalidates uncommitted progress; retries resend retained input. Tests exercise
these transitions with deterministic suspended/failing decoders.

## Qualification

All recognition uses the production Swift providers and disk-backed channel. Python prepares and
scores public inputs; it performs no speech inference. The shipped executable was retained with its
SHA-256, and the final candidate was separately pinned so later builds could not replace the executable
being qualified. Both use identical installed weights, language hints, input manifests and feed mode.

The final source and executable hashes were frozen before inspection of final-cohort results. The
cohort contains 20 English and 20 Romanian FLEURS recordings, each at original gain, RMS-0.0012 quiet
and seeded 10 dB additive-noise conditions, plus three no-speech sentinels: **123 pairs and 2,661 reference
words**. Its per-language text IDs exclude every earlier consulted holdout. Previously failed holdouts
became development evidence and were not reused as unseen evidence.

Source audio is [Google FLEURS](https://huggingface.co/datasets/google/fleurs/tree/70bb2e84b976b7e960aa89f1c648e09c59f894dd),
revision `70bb2e84b976b7e960aa89f1c648e09c59f894dd`. Supplementary meeting speech comes from the
[AMI Meeting Corpus](https://groups.inf.ed.ac.uk/ami/download/), using the previously frozen ES2002a
short replies, turns and continuous minute. Both datasets provide this research audio under CC BY 4.0.
No personal audio or Vault content was read. Native model revision remains
`bd13ddde81d3134719c520845346b3252daf3175`, with the pinned FluidAudio runtime.

Cross-version comparisons retain **actual outputs**. Equal window traces cannot establish equal PCM
when preprocessing changes, so the scorer rejects `boundary-effect` attribution for these comparisons.
The raw gate requires fewer errors, a negative upper clustered-bootstrap bound, no subgroup error
increase and no new watched critical-word, whole-utterance or noise-only loss.

The critical-value guard had independently reproducible false positives for explicit English compound
numbers such as “two thousand five” versus “2005”. Its bounded grammar now canonicalizes explicit
cardinal expressions; WER still scores original tokens. Tests reject changed values, missing
multipliers, homophones and malformed expressions. This is a conservative retention guard, not a
complete semantic or multilingual number parser. The previous raw scores and failed outputs remain
in their original reports.

| Final cohort | Shipped WER | Candidate WER |
| --- | ---: | ---: |
| English, original gain | 43.72% | 6.93% |
| English, quiet | 31.39% | 7.79% |
| English, noise | 47.19% | 9.74% |
| Romanian, original gain | 8.47% | 8.00% |
| Romanian, quiet | 43.53% | 9.88% |
| Romanian, noise | 31.76% | 29.41% |
| Combined | **34.65%** | **11.80%** |

Errors fell from **922 to 314**. The paired WER difference is −22.85 percentage points, with a
95% utterance-cluster bootstrap interval of **−29.93 to −16.50 points**. All three no-speech sentinels
produced no words. Condition variants are resampled together, rather than counted as independent
recordings. Earlier consulted cohorts also pass the final gates: 31.01% → 12.18%, 38.02% → 18.73%,
and 36.63% → 14.02% WER.

| Supplementary comparison | Shipped WER | Candidate WER |
| --- | ---: | ---: |
| Paced English/Romanian subset | 44.76% | 30.48% |
| Automatic-language subset | 52.38% | 35.24% |
| Continuous meeting minute | 8.97% | 8.97% |
| Natural replies and turns, verbatim scoring | 13.07% | 14.20% |

The last row triggers the raw supplementary subgroup guard. Exact review of every changed word shows
one difference: “was gonna choose” becomes “was going to choose”; all other words in all ten clips are
unchanged. This is an equivalent spoken-contraction expansion, not lost meeting content. The raw
failure remains recorded, with an explicit review artifact; neither WER nor the gate was rewritten to
hide it. The frozen main cohort independently passes the original raw gate.

Configured-default native checks used two independent sources without a boundary override. Both
retain the original quiet negation. Final headless completion receipts verify **38 focused, 1,253 full,
450 stress and 486 race tests**, with no sanitizer findings. The app was rebuilt without a visible
workflow. Native automatic-language and paced comparisons have no watched critical regressions.

## Evidence and limits

The [evidence archive](data/nemotron-transcription-2026-11-14) retains input/model/source/executable checksums, complete native reports, gain
controls, rejected candidates, scores and discovered-test completion receipts. Audio stays outside Git.
Disposable generated conditions are removed only after checksum and open-file checks. Canonical public
inputs, installed models and the person's Vault are outside that cleanup.

The final behavior is enabled automatically for continuous Nemotron channels. Short Talk/dictation
keep baseline boundary selection; they share input validation and bounded normalization. Parakeet keeps
its qualified policy, and Whisper's default remains unchanged pending separate qualification. There is
no new user setting or persisted format migration. GUI, microphone and live-call checks are not claimed;
there is no CPU, battery or device-presentation latency claim.
