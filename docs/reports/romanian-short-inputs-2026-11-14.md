# Romanian short-input qualification — 14 November 2026

The shipped Whisper short-input fix passed the existing raw cross-version quality gate on a new
Romanian lexical set: **100% → 67.95% WER**. This adds evidence for complete short Romanian words;
it does not establish conversational accuracy. Automatic language detection remains weak on isolated
words, especially quiet or noisy ones. No recognition code or default changed in this qualification.

## Frozen inputs and comparison

The [public Romanian pronunciation collection](https://commons.wikimedia.org/wiki/Category:Lingua_Libre_pronunciation-ron)
provides human recordings with structured spoken-text references. Selection required the MediaInfo
`P9533` text to match the predetermined Romanian term exactly, a complete original duration of
0.2–1.0 seconds, a reviewed public license and a maximum of sixteen files per contributor label.
References cover replies, time/place words and numbers. No words were cut from longer sentences.
Audio was resampled to mono PCM16 at 16 kHz without trimming or gain changes.

Before any recognition, selection required at least 24 files from three contributor labels. The first
attempt produced only 23 files from two labels. A broader fixed term list produced 25 from two.
Including explicitly public-domain CC0 recordings, previously omitted by the license allowlist,
produced **26 files from three contributor labels: 16, 9 and 1**. Those selection attempts, their
metadata and failures are retained. No model output was consulted to revise selection. Contributor
labels do not independently establish distinct speakers, demographic coverage or balanced sampling.

Each recording has original-gain, RMS-0.0012 quiet and seeded 10 dB Gaussian-noise variants, with no
added silence. Each variant is evaluated with explicit Romanian and automatic language selection:
156 speech conditions. Three new 0.9-second noise-only controls run under both language settings,
for **162 paired conditions** total. Source SHA-1/SHA-256, canonical and derived hashes, exact references,
public authorship/license information, preparation versions and metadata are retained. Licenses are
CC BY 4.0, CC BY-SA 4.0 or CC0 as recorded per file. Audio and model weights are outside Git.

The unchanged gate was fixed before transcription: fewer raw errors, a negative upper 95% clustered
bootstrap bound, no language/condition subgroup increase and no critical-value, whole-utterance or
noise-final/draft regression. Variants and language settings cluster by original recording. Both
executables use the production disk-backed meeting channel and their **baseline boundary arm**.
The benchmark's adaptive arm is supplementary, not Whisper's production default.

| Build | Commit | Executable SHA-256 |
| --- | --- | --- |
| Before the short-input fix | `47ed667` | `4534c0814d813834903690eaa84de27927bc9008ed33eef4ad79b5c4efc5c03a` |
| Shipped short-input fix | `01ab624` | `5bbe44eb5f37acf4b6e9701f8f2b7f975f01b39779c54a3b651dcad638e30476` |

The first executable was built in an isolated checkout. Both were copied to distinct immutable paths
with their own resource bundles before qualification. The shipped executable hash matches the earlier
English qualification. Both use installed Whisper Turbo revision
`0f63a7800b00dd0226abd051b906c246e1907482`; no weights or SDK source were patched.

## Raw results and limits

| Language selection / condition | Cases | Before WER | Shipped WER |
| --- | ---: | ---: | ---: |
| Romanian / original | 26 | 100% | 34.62% |
| Romanian / quiet | 26 | 100% | 57.69% |
| Romanian / noisy | 26 | 100% | 57.69% |
| Automatic / original | 26 | 100% | 69.23% |
| Automatic / quiet | 26 | 100% | 96.15% |
| Automatic / noisy | 26 | 100% | 92.31% |
| All speech | 156 | 100% | 67.95% |

The earlier runtime skipped these short inputs: all 156 reference words were deleted. The shipped
build had 76 substitutions, 25 deletions and five insertions. The paired WER-delta interval was
**−44.23 to −19.87 percentage points**. There were no subgroup or critical regression flags.
All six noise-only language/control pairs produced no final words or drafts in either build.

These are deliberately short, isolated public lexical recordings. They do not establish that numbers
are reliably preserved in conversation, that automatic language selection can identify any isolated
word, or that longer-window noise handling is fixed. Original word-token WER is unchanged; numerical
forms are equivalent only in the scorer's separate conservative value-retention guard. No hypothesis
was rewritten or replaced with a matched-input result.

## Review

Both native reports completed all 324 expected rows without recognition failures. Completion markers,
input/model identities, report hashes and the unchanged raw gate were verified. This is file-only
quality qualification, not a timing benchmark. No microphone, call application, GUI, account or
personal recording was opened. Full engineering checks for the unchanged implementation remain in
the [short-input implementation report](whisper-short-inputs-2026-11-14.md).

Pre-commit review checked reference provenance, complete-file duration, deterministic transforms,
selection chronology, baseline-arm selection, raw failures and archive checksums. Live and Romanian
conversational qualification remain deferred. The next investigation addresses longer-window noise
separately and must preserve this shipped short-input behavior.

Evidence: [checksums and compressed artifacts](data/romanian-short-inputs-2026-11-14/checksums.json).
