# Adaptive meeting transcription — 14 November 2026

The accepted policy improves retention of quiet speech in continuous Parakeet captures. On the final
English/Romanian holdout, word error rate (WER) fell from **29.49% to 9.10%**. Every measured
language/condition group improved or stayed level, with no new critical-word loss or noise-only words.
A continuous minute retained the baseline transcript exactly. These are results for the specified
public corpus and conditions, not an estimate of error rates in everyone's meetings.

The policy is recommended by the Parakeet provider for continuous transcription. Talk/dictation keep
their established short-utterance behavior; other providers keep their own current policy. This changes
no saved IDs, model preferences or archive format, and adds no user setting.

## Implementation and experience

Each source owns a `SpeechBoundaryPolicy` value in its window buffer. After 200 ms of quiet normalized
16 kHz samples, it can lower the old RMS gate of 0.002. The gate uses the greatest of 0.0005, 1.8 times
the median of at most 200 quiet frames, and 0.2 times the source's largest observed frame RMS. It remains
capped at 0.002, so every frame accepted by the old gate remains accepted. Recognized voice does not
enter the noise estimate. Calibration resets with its channel; no state is shared between application
and microphone channels or retained in the prepared model.

A strong source retains its conservative level reference across pauses. A loud transient or earlier
loud speaker can consequently limit later quiet-speech improvement in that channel. This deliberate
tradeoff prevents quiet gaps from repeatedly changing normal-volume utterance boundaries. It does not
attempt gain tracking for each person in mixed audio.

The user gets more complete quiet phrases through the existing live transcript. The 600 ms silence
interval, 12-second window cap, 24-second memory bound, leading context and timestamp overlap are
unchanged. Moving cuts to quiet dips and extending the silence interval were tested and rejected.
There is no extra recording, capture permission, network service, timer or UI update producer.

`SpeechRecognitionContext.purpose` separates capture duration from inference priority. Providers own
their recommendation; `WindowSpeechModel` applies it to continuous channels. The explicit request
override supports paired qualification. A separately injected, typed observer counts inference requests
and input samples outside audio locks. Production does not install it, and it writes nothing to the
app's diagnostic archive.

Non-finite sample energy fails before reaching the decoder. Buffer capacity checks avoid addition
overflow. Existing failure delivery and final drain remain intact; tests cover invalid audio, short
answers, the last partial frame, overlap, bounded calibration, source reset, recommendation/override
routing and inference-cache accounting.

## Inputs and comparison

The baseline is the finite-input behavior of `ca3bba6`, with the same model weights, language hint,
decoder, audio store, windowing and timestamp reconciliation. The candidate is the frozen `v6` policy.
Parakeet Ultra revision is `95eaa59a39d4394f047a4dc5cce480388a60d1b6`, using the pinned native
FluidAudio runtime on an Apple M4 Pro with 48 GiB memory. Source, executable, model and input checksums
are retained with the results.

The primary speech source is [Google FLEURS](https://huggingface.co/datasets/google/fleurs/tree/70bb2e84b976b7e960aa89f1c648e09c59f894dd),
revision `70bb2e84b976b7e960aa89f1c648e09c59f894dd`. Sixteen development recordings calibrate the policy;
40 final test recordings contain 20 English and 20 Romanian utterances. Selection uses the first distinct
per-language text IDs in pinned archive order with mono audio and duration 3–20 seconds. The final test
excludes the per-language IDs used in earlier failed holdouts. Its recognition results were not inspected
until after calibration, the known continuous-stream check, focused tests and source/executable freezing.

Every recording has three deterministic conditions: original gain, RMS normalized to 0.0012, and seeded
10 dB additive Gaussian noise. All receive 0.5 seconds of leading and 1.2 seconds of trailing silence.
Normalization can amplify an already quieter clip. Added noise affects the original clip, not the added
silence. This intentionally stresses quiet detection and does not represent a distribution of room noise.
Three noise-only sentinels cover zero, low and higher noise levels. The final holdout has 123 paired
fixtures: 120 speech conditions plus three sentinels, with 2,682 reference words across condition variants.

Supplementary natural meeting speech comes from the [AMI Meeting Corpus](https://groups.inf.ed.ac.uk/ami/download/),
manual annotations 1.6.2 and the ES2002a headset mix. Frozen selection takes six short replies, four
10–20-second turns and seconds 60–120 continuously. All annotated speakers contribute words in start-time
order. Overlap and disfluencies make these useful regression checks rather than a meeting leaderboard.
Google FLEURS and the AMI project supply these public research datasets under CC BY 4.0; their source
URLs and checksums are included. No personal recording or Vault content was used.

The native tool uses the production `DiskSpeechAudioStore` path and 100 ms input packets; analysis stays
at the production 10 ms frame size. It loads one model and alternates policy order by fixture. Warmup uses
development audio when the input supplies it. Replay tests exercise catch-up/drain; paced real-time tests
exercise drafts and finalization. Every result is written atomically, and scoring requires all expected
paired rows, a final completion marker and no native recognition failures.

## Final results

| Final holdout group | Baseline WER | Adaptive WER |
| --- | ---: | ---: |
| English, original gain | 36.52% | 4.06% |
| English, quiet | 33.89% | 5.49% |
| English, noise | 41.53% | 7.16% |
| Romanian, original gain | 8.00% | 7.79% |
| Romanian, quiet | 41.47% | 10.53% |
| Romanian, noise | 18.32% | 18.32% |
| Combined | **29.49%** | **9.10%** |

The baseline has 285 substitutions, 480 deletions and 26 insertions; the candidate has 193, 39 and 12.
The paired WER difference's 95% bootstrap interval is **−27.93 to −14.13 percentage points**. The scorer
resamples 40 original utterance clusters, keeping generated conditions together, using 2,000 samples and
a fixed seed. This supports improvement for this cohort without counting the three generated variants
as independent recordings.

| Supplementary check | Pairs | Baseline WER | Adaptive WER |
| --- | ---: | ---: | ---: |
| Development calibration, all conditions | 51 | 31.89% | 14.40% |
| Real-time English/Romanian subset | 6 | 41.90% | 28.57% |
| Automatic-language subset | 6 | 41.90% | 28.57% |
| Natural meeting replies and turns | 10 | 15.91% | 15.91% |
| Continuous real-time meeting minute | 1 | 13.79% | 13.79% |

Every natural excerpt retains its baseline per-clip WER; the continuous minute has identical text.
All no-speech outputs are empty. The small supplementary sets establish no measured regression here;
unchanged groups do not pass the separate statistical improvement gate, and are not described as an
improvement. The primary heldout cohort passes that gate.

WER uses Unicode-normalized, case-folded tokens while preserving Romanian diacritics. It counts raw
word-format differences. The separate critical-retention check watches negations and number values,
including equivalent cardinal word forms. It is a conservative token check, not a semantic correctness
proof. The automatic-language check is a small development subset, not a second independent holdout.

## Work and latency

Each holdout policy receives 1,463.64 seconds of fixture audio, including generated variants and padding.
The baseline requests 517 inferences over 28,521,120 input samples; the candidate requests 511 over
39,410,080. Replay processing wall time increases from 79.87 to 116.35 seconds. Retaining previously
missed speech requires **38% more decoder input** in this run; fewer calls do not imply less work.
Processing includes feeding and backlog I/O and is not a CPU-time measurement. Real-time duration
includes the intended wait, while release-to-finalization is recorded separately in raw results. This
change does not claim a speed or finalization-latency improvement.

## Rejected experiments and scoring correction

- The initial pilot fed unbacked whole clips, diluting short voiced frames in surrounding silence. Its
  results are excluded. The corrected runner and scorer require the production meeting backing path.
- `v2` selected relatively quiet cuts and extended weak-voice silence tolerance. Its first holdout
  improved overall but increased noisy-Romanian errors, so it was rejected.
- `v3` required a complete quiet slice before moving a cut. Its fresh holdout improved, but the known
  continuous-minute check increased from 20 to 22 errors out of 145 words. It was rejected.
- `v4` kept the existing cuts and silence interval and adapted only the noise gate. The same continuous
  regression remained, showing that changing cuts was not required to reproduce the issue.
- `v5` added a recent source-level reference that expired across quiet gaps. It reduced the continuous
  discrepancy to one error but still failed the check. Its prepared holdout remained unseen.
- `v6` holds the conservative source reference for the channel lifetime. It preserves the continuous
  baseline and was frozen before evaluating that unseen holdout. All required quality checks passed.

One evaluation correction was made after `v3`: the literal-digit check treated “ten,000” as losing the
value in “10,000.” Equivalent cardinal forms now match in the value-retention check. Raw WER still
counts the formatting error; changed values, missing digits and homophones remain failures. Both the
original flagged score and corrected score are retained. This did not rescue `v3`'s continuous-stream
regression or change any WER count.

## Verification and limits

The focused run verified completion of 20 selected Core/Speech tests. An initial sanitizer run
reported six assertion issues in two existing 50 ms startup-deadline tests, without a data-race report:
speech preparation consumed the deadline before the intended microphone/success stage. Deadline
scheduling is now an injected, cancellation-owned value. Three focused tests explicitly expire the
intended stage and force a late callback after cancellation; they no longer depend on winning a 50 ms
scheduler race. The production 45-second budget and queued delivery remain unchanged. A separate completion test assumed one queue checkpoint completed
a nested drain; it now awaits the actual completion event. Four focused lifecycle tests passed, followed by fresh full checks. Both
failed runs are retained alongside the final receipts.

Final qualification passed with discovered-test completion receipts: **1,232** standard tests through
`make check`, **438** through `make stress`, and **477** through `make race-check`. The extra focused
lifecycle run verified four tests. The linked data directory retains selections, completion receipts
and failure evidence. Native GUI, live microphone and live call-app checks were not run. The file-only runner opens no capture device.

The evidence covers one native model revision and English/Romanian, with narrow automatic-language
and natural-meeting supplements. It does not establish every language, accent, room, device, echo or
speaker overlap, nor does any cohort guarantee improvement for every future utterance. The application
keeps other providers and short captures on their established policy until separately qualified.

[Raw results, input/model/source checksums and completion receipts](data/transcription-boundaries-2026-11-14/)
are bounded and contain public-corpus references and hypotheses for inspection. Audio remains outside
Git. The [reproduction guide](../../Benchmarks/Speech/README.md) restores exact inputs and documents
comparison and scoring commands.
