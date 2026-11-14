# Whisper longer-window noise investigation — 14 November 2026

**No broader Whisper policy is enabled.** Two independently tested changes failed the predeclared
speech-quality gates. The shipped short-input implementation remains intact, with the separately
reviewed [Romanian qualification](romanian-short-inputs-2026-11-14.md). A native learned detector is
promising in exploratory controls, but has not established an end-to-end transcription improvement.

## Independent candidates

The acoustic-only candidate required the existing fresh WebRTC speech check before every Whisper
window. Shared channel admission owned cancellation and inference accounting; the provider received
an explicit validator dependency. Decoder options, captured PCM and result confidence policy stayed
unchanged. Focused channel tests exercised long-window rejection, fresh classifiers, failure, cancelled
analysis and draining without an inference. Fourteen discovered tests completed with checked receipts.

The confidence-only candidate instead applied the SDK's existing finite average-log-probability and
compression limits to all returned segments. It retained shipped short-only acoustic admission and
all native decoder settings. Provider tests exercised invalid confidence and preserved word/language
mapping; four checked tests passed. These were separate executables, not a combined candidate.

Both source snapshots and executables were frozen before their outcomes. All recognition used the
production disk-backed meeting channel, installed Whisper Turbo revision
`0f63a7800b00dd0226abd051b906c246e1907482`, and baseline boundary arms from both builds. Native model/SDK
files were not patched. The contract retained the existing raw WER, subgroup, critical-value and
noise-final/draft gates. No thresholds or references were changed after failure.

| Build | Executable SHA-256 |
| --- | --- |
| Shipped `01ab624` | `5bbe44eb5f37acf4b6e9701f8f2b7f975f01b39779c54a3b651dcad638e30476` |
| Acoustic admission only | `be1ef33d54fca5768abd244f2553955ca4e969ca40003b5a8c8ab96149fbd502` |
| Confidence acceptance only | `7ac0f8c8773cf1412f135c8a06b5ec4d1b9f51cb5df58d814e8dcc44c49ad17f` |

## Raw transcription results

Development reused eight English and eight Romanian [FLEURS](https://huggingface.co/datasets/google/fleurs)
recordings under original, quiet and seeded 10 dB noise conditions, plus three noise-only sentinels:
51 pairs and 903 reference-word occurrences. Conditions, hashes and references remained unchanged.

| Candidate | Shipped WER | Candidate WER | Decision |
| --- | ---: | ---: | --- |
| Acoustic only | 32.56% | 31.89% | Reject: English/noise increase; improvement interval includes zero |
| Confidence only | 32.56% | 33.33% | Reject: three subgroup increases and a lost number |

Acoustic-only English/noise WER rose from 44.68% to 46.10%. Its paired WER-delta interval was
−0.87 to +0.10 percentage points. The raw failure is retained without substituting equal-input
hypotheses or attributing away sampling variation.

Confidence-only English/noise rose to 46.81%, Romanian/quiet from 42.50% to 45%, and Romanian/noise
from 29.38% to 30.63%. `ro_ro-dev-1598::noise` became empty and lost the retained canonical value `3`.
Its paired interval was 0 to +2.17 percentage points. Native low confidence is not sufficient evidence
that real speech should be discarded.

Forty previously prepared English/Romanian recordings were checked against every available decoded
result archive before being reserved for a fresh evaluation. A misleading `next-source` filename was
rejected because its IDs had already been decoded; the verified `validation-source` cohort has no
such overlap. Its 123 test conditions were prepared but **never transcribed**, because both candidates
failed development. They remain input provenance, not qualification evidence.

## Real noise controls

The [MUSAN corpus](https://www.openslr.org/17/) includes labeled non-speech recordings. A pinned
[mirror](https://huggingface.co/datasets/FluidInference/musan/tree/3edcfdf89b56dbe6a395ff29f9c29489e03d1321/noise)
provided the checksum-verified files. Selection used source titles before model output: environmental
sounds and devices, excluding crowd, conversation, music and vocal-event selections. Per-source
credits and licenses are retained; original recordings are outside Git.

The prepared plan contains 24 sources in original and RMS-0.0018 variants, with English/Romanian
hints. The exploratory ASR pilot uses the first twelve original-level sources in that fixed plan under
both hints: **24 pairs**. Remaining prepared conditions were not decoded and are not claimed as
validation. Each input retains at most the first twelve seconds of labeled non-speech.

| Pilot | Inserted words | Noise regression guard |
| --- | ---: | --- |
| Shipped | 39 | Reference for comparison |
| Acoustic only | 36 | Failed: a new noise-caption increase |
| Confidence only | 13 | Passed noise guards; speech-quality gate still failed |

There are no reference words in these noise-only controls. The scorer's displayed zero WER and
zero bootstrap interval do not mean perfect recognition or a passed improvement gate. Insertions
and final/draft regression flags are the meaningful measures here. Improved noise rejection did not
override the confidence candidate's loss of real Romanian speech.

On all 24 original-level sources, the native WebRTC check classified **21 as speech**. Rescaling an
analysis copy to RMS 0.024 / peak 0.125 reduced that to **18**, still failing the gold controls. Neither
rescaling nor a changed gain policy was added to production. An initial probe correctly rejected an
overlength speech control; the complete comparisons use the corrected bounded request. All six
within-bound speech controls were detected in both completed probes.

## Learned detector probe

The existing pinned native SDK also supports [Silero's detector](https://github.com/snakers4/silero-vad)
through its [Core ML conversion](https://huggingface.co/FluidInference/silero-vad-coreml). The research
probe downloaded and verified five files totaling **1,063,425 bytes**, pinned at conversion revision
`b419383c55c110e2c9271fa6ee0ea83d03c70d96`. It loaded that explicit model directly with CPU-only Core ML;
SDK constructors capable of downloading were not used. No model was installed into the person's
speech-model store or added to the application catalog.

At the unchanged SDK threshold of 0.85, both captured audio and existing detector-only gain profiles:

- Classified **2 of 24** non-speech sources as speech: fax and crickets. Their maximum probabilities
  were about 0.9976 and 1.0, so high probability alone does not solve the remaining false positives.
- Detected all **117 speech conditions**: thirteen eligible FLEURS recordings in original/quiet/noisy
  variants and 26 complete Romanian lexical recordings under the same three conditions. These are
  39 underlying recordings, not 117 independent speakers or samples.
- Returned identical results for the first noise fixture when repeated after intervening sources,
  checking the pinned SDK's fresh recurrent-state behavior.

The original 77-fixture probe preserved its four failed assertions: two noise errors under each
analysis profile. A separately declared 65-fixture speech challenge passed one checked native test.
Gold labels were not rewritten to make the noise probe pass.

These are consulted development controls. The conversion's model card lists MUSAN subsets, so this
noise comparison is not evidence of independent held-out detector generalization. Nor does detector
recall prove preserved transcripts, numbers, timestamps, cancellation or application lifetime behavior.
A future integration needs non-MUSAN noise, fresh end-to-end speech/noise evaluation and explicit model
ownership, installation, inference admission and cancellation. This investigation does not enable it.

## Review and retention

Both production prototypes were removed after preserving complete source snapshots and raw outcomes.
Frozen production source hashes match the shipped implementation. The only retained Swift change is
an opt-in, file-only native detector replay helper: bounded manifests/files/samples, finite input/output
checks, explicit local model ownership and atomic numeric output. Default tests do not load its model,
read research audio or open a capture device. Execution classification remains headless.

The final repository passed `make check` with **1,270 selected headless tests**, checked completion
receipts, and **157 Python checks**. Earlier stress/race receipts for the unchanged production speech
implementation remain in the implementation report; those suites were not repeated for this
research-only helper. No GUI, live microphone, call app or native performance check was run.

Evidence retains contracts, source snapshots, input/model hashes, selection scripts, public raw
hypotheses, numeric detector results, failures and completion receipts. Disposable audio, temporary
model/checkout/build copies and frozen executables are cleaned only after exact-path and live-user
checks. Installed models and personal Vault data are outside cleanup scope.

Evidence: [checksums and compressed artifacts](data/whisper-long-window-noise-2026-11-14/checksums.json).
