# Whisper short-input decoding — 14 November 2026

Whisper now decodes confirmed speech in windows of one second or less, which the pinned runtime
previously skipped. A frozen cross-version comparison passed the predeclared raw quality gate:
**100% → 64.48% WER** on 117 short-speech conditions from 39 previously untranscribed utterances.
All 36 fresh short-noise inputs produced no final words or drafts. Recognition remains imperfect;
this qualifies minimum-length handling, not broader adaptive boundaries or universal noise rejection.

The fix applies automatically wherever the Whisper provider is selected, including meeting final
windows, Talk and dictation. It adds no setting, permission, migration, producer or network inference.
The other providers retain their qualified defaults. Live microphones, call apps and GUI workflows
were not exercised because live validation was explicitly deferred.

## Root cause and implementation

WhisperKit 1.1.1 at `1bbc57cb7fe6410248a685b1c5a3c6d56adc2ed4` defaults `windowClipTime` to one second.
Its `TranscribeTask` loop requires the remaining input to be strictly longer than that guard.
Four previously empty meeting replies were 0.80–0.97 seconds: they reached the native API but did
not enter decoding. The earlier report's engine-call interpretation is corrected separately;
its original hypotheses, scores and rejected broader candidates remain intact.

The independently implemented provider adapter extends nonempty short decoder input to 16,001 samples,
without changing the captured window, original samples, channel retirement or transcript clock.
`SpeechInputPadding` shares the bounded, checked allocation policy with Parakeet. Empty input remains
empty; invalid native guard values and non-finite audio fail recoverably.

Newly eligible windows require an injected `SpeechWindowValidatorFactory` in the shared channel.
`SilliesAudio` owns fresh strict native WebRTC classification and the existing 180 ms speech-onset
policy. A separate analysis copy uses the shared Core gain policy: maximum 16, peak ceiling 0.125,
RMS ceiling 0.024. Decoder normalization retains its existing maximum gain of two. No classifier
history crosses sources, attempts or windows. Longer windows never construct the validator.

Only newly extended results must meet the SDK's existing finite average-log-probability and compression
limits. Decoder settings, samples, seek behavior and result acceptance for already supported windows
are preserved. Each request receives its own immutable `WhisperSegmentSeeker`; its existing prompt
alignment adaptation is retained. For extended input only, a non-advancing seek consumes the bounded
window. Checked offset arithmetic retires invalid ranges safely. This addresses a code-reviewed loop
hazard and has a deterministic zero/backward-timestamp regression; no production hang was reproduced.

The provider remains isolated on its native worker, behind shared inference admission. The channel
owns cancellation, finalization, output clamping and failure delivery. No new unchecked concurrency
conformance or independent timer was added. Acoustic failures follow the existing deliberate error
path; rejected noise retires normally without claiming an inference call.

## Rejected prototypes

Minimum-length padding alone recovered real replies but also produced captions on synthetic noise.
An initially empty short reply returned eight low-confidence invented words (average log probability
−13.607). Applying native confidence limits removed that result, but another short noise window still
returned a high-confidence word. These versions were not shipped.

The SDK's `noSpeechProb` is currently hardcoded to zero. A separate experimental observer of the initial
silence-token probability did not distinguish the examined speech and high-confidence noise controls:
both were around 10⁻¹⁰. That observer and its math were removed completely. Its source snapshot and raw
measurements remain evidence, without changing the SDK's recorded zero field. A detector-only gain of
two also missed a real short reply; the bounded peak/RMS analysis policy passed all 18 consulted
speech/noise controls before freezing the final candidate.

## Qualification

Weights were the already installed Whisper Turbo revision
`0f63a7800b00dd0226abd051b906c246e1907482`: 21 catalog-verified files, 629,518,418 bytes. SDK source and
model weights were not patched. Executables were copied to distinct immutable paths before testing:

| Build | Executable SHA-256 |
| --- | --- |
| Shipped baseline `47ed667` | `14a67753b7bcad84f5b14b383a1a3af1c429deda8b571e263b170f927e148961` |
| Qualified short-input candidate | `5bbe44eb5f37acf4b6e9701f8f2b7f975f01b39779c54a3b651dcad638e30476` |

The predeclared contract selects the **baseline arm from both binaries**, matching Whisper's actual
production boundary setting. The benchmark's adaptive arm is supplementary evidence, not its default.
Primary scoring uses actual raw hypotheses, unchanged critical-loss/subgroup guards and the existing
95% clustered bootstrap; no boundary-effect substitution or transcript rewriting is allowed.

Public inputs come from the [AMI Meeting Corpus](https://groups.inf.ed.ac.uk/ami/download/), distributed
under CC BY 4.0. Selection used annotation timing before transcription: one to three words, after
120 seconds, globally separated from other annotated words, 0.1 seconds of context on each side and a
maximum total duration of 0.99 seconds. Previously examined ES2002a intervals were excluded. This
produced nine new ES2002a, fourteen ES2002b and sixteen ES2002c excerpts. Each has original, RMS-0.0012
quiet and seeded 10 dB Gaussian-noise conditions, without added silence. Source coordinates, original
and derived hashes, selection scripts and the acceptance contract are retained.

| Primary short-speech condition | Cases | Baseline WER | Candidate WER |
| --- | ---: | ---: | ---: |
| Original | 39 | 100% | 54.10% |
| Quiet | 39 | 100% | 62.30% |
| Noisy | 39 | 100% | 77.05% |
| All | 117 | 100% | 64.48% |

There were 183 reference-word occurrences across the three conditions: baseline deleted all 183;
candidate had 29 substitutions, 86 deletions and three insertions. The paired WER-delta interval was
**−48.77 to −23.87 percentage points**, with no critical or subgroup regression. The bootstrap clusters
conditions by utterance; these are only three English meetings, not independent evidence across
languages, speakers, devices or arbitrary environments. A subsequent
[Romanian lexical qualification](romanian-short-inputs-2026-11-14.md) passed on complete short words,
including automatic language controls. Romanian conversational coverage remains unverified;
these limited results are not a general multilingual accuracy claim.

Fresh noise controls fixed four signal types (Gaussian noise, line hum, a pure tone and clicks),
three durations (0.2, 0.5, 0.95 seconds) and three levels before transcription. Both builds produced
zero final/draft words; the candidate admitted zero decoder requests. Twelve newly eligible short
windows in the older burst-noise set also produced no words or drafts.

The full older 30-case burst set includes windows longer than one second. Its raw cross-version score
**failed** the broad noise-regression guard: four versus five inserted words, with two new final-word
flags on 28,000-sample windows. Those complete input/inference traces match, and the implementation
preserves their decoding path. Their raw results are retained and are not normalized into a pass.
This was anticipated by the scoped acceptance contract: it requires zero new words on newly eligible
short noise and makes no broader noise-quality improvement claim. Broad Whisper noise suppression
remains unresolved.

A repeat with the identical baseline executable produced eight inserted words and three new flags
against its first four-word result. This independently demonstrates output variability on those
longer controls; it does not replace either cross-version result or turn a failed raw score into a pass.

Supplementary raw controls retained every output: the 51-case English/Romanian development set was
35.33% → 32.12% WER with no critical/subgroup regression, and ten paced natural meeting replies/turns
were 25% → 22.73% with no regression flags (the small-set bootstrap included zero). All ordered
inference traces for windows longer than one second matched across builds. These controls check for
regressions; their aggregate differences are not attributed to improved longer-window decoding.

A final native replay of the 0.97-second “Okay” fixture recorded **one actual native decoding window**
and the recognized word. The benchmark's engine-request counts exclude internal zero padding and
are not used as proof of SDK decoding. Functional regressions verify that padded output cannot extend
the capture clock, invalid/overflowing inputs recover, failures deliver once, cancellation drains,
and validators are never constructed for longer inputs.

The one-second, automatic-language silence input used by model-update validation also recorded one
actual native decoding window in a separate checked replay. The validation call now exercises the
decoder rather than returning through the minimum-length guard.

## Engineering review and retained evidence

Pre-commit review checked dependency injection at all six provider construction sites, immutable
native ownership, scoped admission/confidence/seek behavior, checked arithmetic and the shared
Parakeet padding path. Rejected posterior/recovery hooks are absent. Final source hashes still match
the frozen executable's manifest. Formatting, architecture/localization checks and `make check`
passed: **1,269 headless tests**, plus **157 Python checks**. `make stress` passed **456 tests**;
`make race-check` passed **492 instrumented tests**. Discovered-test completion receipts were verified
for all runs. Additional checked runs cover 27 focused tests, 18 public acoustic fixtures in four
tests, and the two actual native decoder replays.

Final check receipts and supplementary controls are recorded with the evidence below. No native
performance claim is made: quality runs can share compute, and no device presentation or frame timing
was measured. No personal recording, account, clipboard or Vault content was read.

The archive retains source snapshots of rejected prototypes and the final implementation, immutable
hashes, manifests, public hypotheses and drafts, scorer decisions, test completion receipts and
preparation scripts. Generated audio and executable copies are disposable and are removed only after
checking their exact paths and live users. Installed weights and the person's Vault stay outside
cleanup scope.

Evidence: [checksums and compressed artifacts](data/whisper-short-inputs-2026-11-14/checksums.json).
