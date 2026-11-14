# Whisper transcription investigation — 14 November 2026

**No Whisper behavior change is enabled.** Acoustic confirmation and decoder-recovery candidates
reduced aggregate recognition errors but failed the raw subgroup or critical-value checks. Their
production changes were removed. Parakeet and the separately qualified Nemotron implementation keep
their existing adaptive defaults; Whisper keeps baseline boundaries. Talk/dictation are unchanged.

This change retains qualification safeguards: bounded live-draft capture, noise-draft regressions,
explicit end-to-end comparison metadata, and a file-only native Whisper replay adapter. It introduces
no setting, migration, background producer, microphone capture or network inference.

## Investigation and ownership

The candidates used the production Swift provider and disk-backed meeting channel with the installed
Whisper Turbo revision `0f63a7800b00dd0226abd051b906c246e1907482`. All 21 model files were checked against
catalog hashes: 629,518,418 bytes. WhisperKit remains pinned at commit
`1bbc57cb7fe6410248a685b1c5a3c6d56adc2ed4`; its checkout was not patched.

The shared channel owned buffering, acoustic dependency injection, cancellation, finalization and
bounded recovery. An audio-owned WebRTC adapter classified complete retained windows using fresh
state, leaving decoder audio intact. A pure Core policy bounded detector-only gain by peak and RMS.
Provider-neutral evidence and attempt values carried decisions into Whisper; decoder settings and
confidence interpretation stayed inside that provider. The inference scheduler forwarded provider
capabilities. There was no new unchecked concurrency conformance or independent timer.

These are **rejected candidate designs**, preserved in the evidence archive rather than active feature
code. `recovery-complete-source-snapshot.json.gz` contains all 40 changed/added candidate files against
base commit `7d22c0d`, including tests. Frozen manifests record source and executable hashes. Earlier
variants have raw results and representative source snapshots; the archive does not claim every early
prototype can independently be rebuilt from final repository source.

Several distinct failure mechanisms were observed:

- Energy-only admission let generative decoding invent noise captions. Stricter native classification
  removed those controls, but aggressive rejection also lost a quiet Romanian recording or soft ending
  in earlier variants. Confirmation therefore had to be tested on both speech and noise.
- Peak-only detector amplification promoted some noise prefixes. A detector-only RMS ceiling of 0.024,
  peak ceiling of 0.125 and maximum gain of 16 passed the retained acoustic controls. This calibration
  is experimental evidence, not a production policy or a claim about arbitrary background sound.
- Identical noisy Romanian 12-second inputs produced different sampled fallback text. Disabling
  temperature fallback alone returned empty text in all six repeats. Completing decoding past the
  first-token abort retained the watched 80/50 values in six repeats. This isolated a decoder issue;
  it did not establish safe behavior for all recordings.
- Completing every confirmed pass changed existing nonempty results. The final candidate instead
  preserved the initial native pass and allowed one confidence-checked recovery only for confirmed
  empty output. Tests bounded retries, cancellation and actual engine-call accounting, including
  through the scheduler. It still failed development and meeting subgroup checks.

No vocabulary tables, phrase blacklists, language-specific thresholds or transcript replacements were
introduced to repair individual examples. No acceptance threshold was relaxed after a failed run.

## Inputs and acceptance

Public speech is [Google FLEURS](https://huggingface.co/datasets/google/fleurs/tree/70bb2e84b976b7e960aa89f1c648e09c59f894dd),
pinned at `70bb2e84b976b7e960aa89f1c648e09c59f894dd`, and the
[AMI Meeting Corpus](https://groups.inf.ed.ac.uk/ami/download/), ES2002a. Both provide the research audio
under CC BY 4.0. Manifests retain source URLs, archive members and original/canonical checksums.
No personal audio, calls or Vault content was read.

Development contains eight English and eight Romanian recordings in original-gain, RMS-0.0012 quiet
and seeded 10 dB Gaussian-noise conditions, plus three no-speech sentinels: **51 pairs**. Each evaluated
fresh cohort contains 20 new English and 20 new Romanian recordings under those conditions, plus three
sentinels: **123 pairs**. The second cohort excluded the first after its results were consulted. A third
40-recording cohort was selected and prepared but **never transcribed**, because the final candidate failed
calibration. It is retained only as input provenance, not validation evidence.

Supplementary controls use six paced condition pairs, six automatic-language pairs, ten natural AMI
short-reply/turn pairs and a continuous minute. Replay uses bounded 100 ms packets with catch-up;
paced controls release those packets at capture speed. All recognition is native Swift; Python only
selects, prepares, verifies and scores inputs. Quality runs establish no GUI frame or device latency
claim. Concurrent native processes were used for quality, so processing times are not performance
comparisons.

Each candidate executable was copied to a distinct path and hashed before qualification. Later builds
never replaced a running candidate. The two final examined binaries were:

| Candidate | Executable SHA-256 |
| --- | --- |
| Complete confirmed pass with RMS bound and one-second replay | `52575175edb220a801dbf72ce3a80bb1c37676fa785009394830af8720638a73` |
| Native initial pass with bounded confirmed-empty recovery | `8caeb5fd33440715a72227916a53104e9d8af2108651437ef5bd6858c35ce37b` |

`qualified-configuration.json.gz` corrects an inherited descriptive sentence in the earlier freeze
metadata; the immutable executable and source hashes identify the actual strict classifier policy.

The primary gate requires fewer total word errors, a negative upper 95% clustered-bootstrap bound,
no language/condition subgroup increase and no newly lost watched negation/number, whole utterance,
noise-only final words or longer noise-only drafts. Small supplementary sets use the regression
checks without claiming statistical improvement. Numeric normalization applies only to the separate
conservative value-retention guard; word errors retain actual formatting differences.

Raw hypotheses are never replaced to make these candidates pass. The scorer rejects boundary-effect
adjustment for end-to-end reports. Some output differences had identical input traces, but other
failures changed windows or decoder policy. Identical traces do not justify dismissing all losses.

## Outcomes

The table reports actual raw outcomes; rows from different cohorts are not temporal quality trends.

| Candidate / control | Pairs | Baseline WER | Candidate WER | Result |
| --- | ---: | ---: | ---: | --- |
| Complete pass, development | 51 | 35.44% | 15.28% | Passed calibration |
| Complete pass, consulted first cohort | 123 | 33.99% | 11.05% | Passed; no longer unseen |
| Complete pass, fresh second cohort | 123 | 44.26% | 14.22% | Rejected: critical-value guard |
| Complete pass, paced controls | 6 | 40.00% | 39.05% | Rejected: Romanian/noise subgroup |
| Complete pass, natural replies/turns | 10 | 23.86% | 25.00% | Rejected: meeting-turn subgroup |
| Empty recovery, development | 51 | 34.66% | 15.50% | Rejected: Romanian/noise subgroup |
| Empty recovery, paced controls | 6 | 41.90% | 35.24% | No regression flags |
| Empty recovery, automatic language | 6 | 43.81% | 35.24% | No regression flags |
| Empty recovery, natural replies/turns | 10 | 25.00% | 26.14% | Rejected: meeting-turn subgroup |
| Empty recovery, continuous minute | 1 | 19.31% | 19.31% | No regression flags |

In the second fresh cohort, the conservative critical guard flagged literal `11a`/`11b` forms becoming
spaced forms in an 802.11 reference. The raw text remains available; this does not prove a changed
protocol meaning. Independent paced and meeting subgroup failures also reject that candidate.

For the final empty-recovery candidate, development Romanian/noise WER rose from **28.125% to 30%**.
One noisy case used identical complete window and inference traces, while another changed boundaries
and added more incorrect tail words. The AMI meeting-turn subgroup also worsened: two additional word
errors overall. These failures were retained without attributing them away as stochastic variation.

The 22 consulted retention/noise/short-reply controls had no critical or subgroup regressions
(54.22% → 22.67% WER), but their bootstrap interval included zero; they did not pass the full statistical
gate. All six short replies reached native decoding. **Four returned empty text in both modes**, even
with candidate recovery; the remaining two had the same text. This is not a claim that short-reply
recognition was fixed.

The earlier complete-pass candidate also passed 48 separately seeded noise-only controls: baseline
produced nonempty final text in 15 cases and live drafts in 11; candidate produced neither in any case.
Actual engine calls were 128 versus 1. This passes noise regression checks, not a WER-improvement gate
with zero reference words. It is evidence about that rejected candidate, not an enabled noise fix.

## Validation, review and retention

The rejected final implementation passed 1,266 checked headless tests, 458 stress tests and 494 race
checks, with discovered-test completion receipts. Additional checked controls exercised the native
acoustic adapter, six repeated decoder recoveries, malformed audio, missing dependencies, failure,
cancellation, scheduler propagation and finalization. Passing these engineering checks did not override
failed recognition-quality gates.

After removing the candidate, the final repository passed 1,253 checked headless tests, 450 stress
tests and 486 race checks, plus 157 Python checks and the actual native replay. Completion receipts are in
`final-repository-test-receipts.json.gz`. GUI, live microphones, device presentation and call-application
workflows were not run. Their absence is not evidence of native workflow coverage.

Pre-commit review removed every rejected production hook and its candidate-only tests, kept the
bounded qualification safeguards, checked draft-overflow/type failures and confirmed existing provider
defaults. The archive retains raw hypotheses/drafts, decisions, manifests/checksums, scripts, source
snapshots, frozen hashes, and completion receipts. Disposable prepared audio, extracted clips and
candidate executables are removed only after exact-path verification and checking for live users.
Installed weights and the person's Vault are outside cleanup scope.

Evidence: [checksums and compressed artifacts](data/whisper-transcription-2026-11-14/checksums.json).
