# Transcription boundary qualification

Compare boundary policies using the production native model, decoder, overlap handling and
`DiskSpeechAudioStore` meeting path. No microphone, call application or audio device is opened.
Python prepares and scores public fixtures; all recognition runs in the Swift executable.

The reviewed input manifests and raw results live in
[`docs/reports/data/transcription-boundaries-2026-11-14`](../../docs/reports/data/transcription-boundaries-2026-11-14).
The [report](../../docs/reports/transcription-boundaries-2026-11-14.md) records rejected candidates,
selection, scoring, work accounting and the limits of the evidence. Audio stays outside Git.

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
noise-only words, and no newly lost negation/number value. Condition variants of the same recording
are resampled together. Small supplementary sets may be inconclusive despite no subgroup increase.

WER uses Unicode-normalized, case-folded word tokens, preserves diacritics and counts substitutions,
deletions and insertions. Numeric word forms are equivalent only in the separate value-retention
check; formatting differences remain word errors. The intentionally conservative check does not infer
missing multipliers or equate homophones. It does not prove semantic correctness.

Work accounting is explicitly injected and content-free: actual inference requests and decoded input
samples, including retries, excluding cache reuse. Processing time includes feeding and backlog I/O;
real-time runs also include the intended wait. Finalization time starts at the last packet's release.
These are local qualification measurements, not routine test timing budgets or device-presentation
latency. More retained speech can require more decoding work.

Keep manifests, source/model checksums, raw results, completion receipts and reports. Remove disposable
restoration copies and generated conditions after verifying their exact paths and that no process uses
them. Installed models and personal recordings are outside cleanup scope.
