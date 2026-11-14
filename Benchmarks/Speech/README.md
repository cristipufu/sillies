# Transcription boundary qualification

Compare boundary policies using the production native model, decoder, overlap handling and
`DiskSpeechAudioStore` meeting path. No microphone, call application or audio device is opened.
Python prepares and scores public fixtures; all recognition runs in the Swift executable.

The reviewed input manifests and raw results live in
[`docs/reports/data/transcription-boundaries-2026-11-14`](../../docs/reports/data/transcription-boundaries-2026-11-14).
The [report](../../docs/reports/transcription-boundaries-2026-11-14.md) records rejected candidates,
selection, scoring, work accounting and the limits of the evidence. Audio stays outside Git. The [provider follow-up](../../docs/reports/shared-stt-boundaries-2026-11-14.md)
records shared configuration, other-provider failures, native defaults and the fresh control cohort.

## Restore inputs

Decompress a reviewed source manifest. `prepare-fleurs.py` streams only the four pinned source
archives until every requested member is found, checks original bytes, converts Float32 to PCM16
without gain changes, then verifies the canonical checksum. It never extracts archive paths.

```sh
python3 -B Benchmarks/Speech/prepare-fleurs.py source-manifest.json /new/corpus
python3 -B Benchmarks/Speech/prepare-quality.py /new/corpus/manifest.json /new/conditions
```

The conditions are unchanged speech, RMS-normalized quiet speech, and seeded 10 dB additive Gaussian
noise, each with 0.5 seconds of leading and 1.2 seconds of trailing silence. Quiet normalization can
amplify a naturally quieter recording. Noise is applied to the original clip, not the added silence.
Three noise-only sentinels per split cover zero, low and higher noise levels. These conditions do not
represent every room, microphone, accent, language, echo or overlapping conversation.

For meeting excerpts, download the two official URLs recorded in the AMI manifest into a source
directory (`annotations.zip` and `ES2002a.Mix-Headset.wav`), then run:

```sh
python3 -B Benchmarks/Speech/prepare-ami.py ami-manifest.json /source/ami /new/ami-excerpts
```

Both downloads and every restored excerpt must match their reviewed checksums. The frozen selection
contains short replies, longer turns and a continuous minute. References include all annotated
speakers in word-start order; overlapping words and disfluencies make this a supplementary check.
The corpus is credited in the report; it is public research audio, never a person's Vault recording.

## Run the native comparison

```sh
source scripts/toolchain.sh
swift build -c release --product SpeechBenchmark
SILLIES_SPEECH_BENCHMARK="$(swift build -c release --show-bin-path)/SpeechBenchmark"
"$SILLIES_SPEECH_BENCHMARK" quality parakeet-ultra /installed/speech-models \
  /new/conditions/manifest.json /new/calibration.json dev replay
python3 -B Benchmarks/Speech/score-quality.py /new/calibration.json /new/calibration-score.json
```

After calibration, freeze source and executable hashes before evaluating a fresh `test` split.
A failed holdout becomes development evidence; do not tune against it and continue calling it unseen.
Use `realtime` instead of `replay` for paced 100 ms delivery and the continuous-minute fixture.
Replay input is bounded to 23.5 seconds per file; real-time input to 90 seconds. Manifests, files,
fixture counts and retained audio are bounded, and checksums also cover warmup inputs.

The tool loads one installed model revision, warms both policies on development audio when supplied,
and alternates their order for each pair. Every result is saved atomically. The scorer requires all
expected paired results, a final completion marker, and no native recognition failures. It exits
nonzero if the main acceptance gate fails: fewer total errors, a negative upper 95% paired clustered
bootstrap bound, no language/condition group increase, no newly lost utterance, no newly generated
noise-only words or longer noise-only live drafts, and no newly lost negation/number value. Draft
capture is bounded to 64 KiB per fixture; overflow fails qualification. Historical reports without
draft fields retain their original final-only coverage, which the scorer reports explicitly.
Condition variants of the same recording
are resampled together. Small supplementary sets may be inconclusive despite no subgroup increase.

WER uses Unicode-normalized, case-folded word tokens, preserves diacritics and counts substitutions,
deletions and insertions. Numeric word forms are equivalent only in the separate value-retention
check; formatting differences remain word errors. The intentionally conservative check does not infer
missing multipliers or equate homophones. It does not prove semantic correctness.

Work accounting is explicitly injected and content-free: actual inference requests and decoded input
samples, including retries, excluding cache reuse. These count engine calls; native token-level
temperature fallback stays inside a call. Processing time includes feeding and backlog I/O;
real-time runs also include the intended wait. Finalization time starts at the last packet's release.
These are local qualification measurements, not routine test timing budgets or device-presentation
latency. More retained speech can require more decoding work.

Keep manifests, source/model checksums, raw results, completion receipts and reports. Remove disposable
restoration copies and generated conditions after verifying their exact paths and that no process uses
them. Installed models and personal recordings are outside cleanup scope.

## Providers with stochastic decoding

Whisper can sample random fallback tokens. Run repeat controls before attributing small output changes
to the gate. The native runner records bounded, content-free traces of every window decision (including
cache reuse) and every actual inference request. For canonical mono 16 kHz fixtures, equal ordered
start/count/completion traces and equal decode calls establish equivalent audio inputs and retirement.

`score-quality.py RESULTS OUTPUT --comparison boundary-effect` retains the complete raw score and
lists every same-input output variation. It additionally estimates the boundary effect using one
shared outcome for pairs whose full window and inference traces match exactly. Changed input or commit
boundaries always retain their actual outputs and critical-loss checks. Missing, incomplete or invalid
traces fail closed. The default `raw` comparison keeps the original strict gate unchanged.

Publish both views and the actual repeat controls for historical comparisons that kept decoding
fixed. A controlled effect score does not establish that the recognizer is deterministic or free
of hallucinations. Current native runs declare `comparison.kind = end-to-end` and require the raw
gate. Equal window traces cannot establish equal decoding policy or preprocessing. The scorer rejects
`boundary-effect` for these runs even when window traces match. Retain failed raw outcomes. The
[Whisper investigation](../../docs/reports/whisper-transcription-2026-11-14.md) records candidates that
reduced aggregate errors but failed subgroup or critical-value checks; production retains its baseline.

## Compare complete application versions

Input normalization and streaming-state changes require actual cross-version outcomes. Retain a
shipped executable and its SwiftPM resource bundles, pin the candidate executable separately, and run
both against the identical manifest, model revision, language hints and feed mode. Never rebuild an
executable path while it is being qualified. Keep every original report.

```sh
python3 -B Benchmarks/Speech/score-quality.py candidate.json comparison.json \
  --baseline shipped.json --baseline-mode baseline --candidate-mode adaptive
```

This validates matching inputs and compares the selected arms with the raw gate. Cross-version
comparisons reject `boundary-effect`: identical start/count traces cannot establish equal normalized
PCM or decoder state. Compound English cardinal values are normalized only in the separate retention
guard; original-token WER and unknown/malformed numeric expressions remain conservative.
