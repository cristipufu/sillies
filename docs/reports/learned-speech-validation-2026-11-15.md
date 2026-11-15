# Learned speech validation — 15 November 2026

**The app keeps its existing speech policy.** A native learned validator was integrated behind the
shared acoustic-validation contract and evaluated with actual Whisper transcripts. Both candidates
failed the predeclared speech-quality gate. Fewer words on a small independent-noise control did not
justify enablement. The backend remains available only through an explicit qualification command;
there is no app registration, catalog addition, model download, setting or migration.

## Implementation and ownership

`SpeechWindowValidating` now supports asynchronous analysis. The shared window channel awaits it,
preserves captured samples and timestamps, checks cancellation and uses its existing explicit failure
path. Short-input WebRTC validation retains its algorithm. `SpeechInputValidation.partitioned` lets
qualification preserve that short-input path while substituting a validator for longer windows.
The split comes from Whisper's existing native minimum, not a corpus-specific threshold.

The isolated `SilliesSpeechActivity` target owns native inference. Its engine holds the installation
lease alongside the weights, validates fixed Float32 tensor names/shapes before the SDK reads native
buffers, and loads/releases the model off the main queue. Each window starts with fresh recurrent
state, so microphone and meeting sources cannot exchange detector history. Requests are bounded to
the existing twelve-second maximum, reject non-finite inputs/probabilities, and check cancellation
between native predictions. A native call already in progress is non-preemptive.

`SpeechOperationQueue` is shared by recognition scheduling and the learned validator: one active
operation, at most four pending jobs, priority ordering, cancellation of queued work and cancellation
checks after active work. `InferenceActivity.performSpeech` centralizes admission and release on
success, failure and cancellation. Neither layer creates a model cache or a timer. The existing app
composition does not depend on the new adapter; only the qualification tool injects it explicitly.

Qualification loads the five checksum-verified files of the
[native Core ML conversion](https://huggingface.co/FluidInference/silero-vad-coreml/tree/b419383c55c110e2c9271fa6ee0ea83d03c70d96),
revision `b419383c55c110e2c9271fa6ee0ea83d03c70d96`, totaling **1,063,425 bytes**. It uses the existing
FluidAudio 0.18.0 SDK, CPU-only direct model loading and its unchanged 0.85 threshold. No
download-capable SDK initializer is used. The temporary research store is separate from personal
installed models. Whisper Turbo weights remain at `0f63a7800b00dd0226abd051b906c246e1907482`;
WhisperKit remains 1.1.1. No decoding options, SDK source or model weights were patched.

## Raw speech results

The declared gate requires fewer total word errors, a negative upper 95% paired clustered-bootstrap
bound, no language/condition increase, no newly lost utterance or critical value, and no new
noise-only final/draft regression. It compares actual end-to-end outcomes, retaining sampling
variation rather than substituting equal-input hypotheses. Source and executable hashes were frozen
before each evaluated candidate; selected arms are the baseline-boundary arm of both builds.

Calibration reused eight English and eight Romanian
[FLEURS recordings](https://huggingface.co/datasets/google/fleurs), each clean, quiet and with seeded
10 dB noise, plus three synthetic noise sentinels: **51 pairs, 903 reference-word occurrences**.
These consulted development inputs are not a fresh speech test. All completed reports contain both
boundary arms, but the comparison selects only the predeclared arm; arms are not extra independent
recordings.

| Candidate | Shipped errors / WER | Candidate errors / WER | 95% paired WER-delta interval | Decision |
| --- | ---: | ---: | ---: | --- |
| Learned validation on all windows | 288 / 31.89% | 289 / 32.00% | −0.61 to +1.01 percentage points | Reject |
| Preserve short-input validation; learned validation on longer windows | 288 / 31.89% | 296 / 32.78% | 0 to +2.24 percentage points | Reject |

Both raw comparisons increased English/clean, Romanian/quiet and Romanian/noise errors. Neither
reported a newly lost critical value. The first candidate removed a 0.9-second final fragment whose
shipped transcript retained the correct ending “various aromatic.” That is a concrete reason to
preserve the already-qualified short-input policy. The second candidate does so and retains that
ending; the threshold and acceptance gates were not tuned after failure.

In the longer-window candidate, English/clean WER rose from **39.01% to 41.84%**, Romanian/quiet
from **41.88% to 43.13%**, and Romanian/noise from **28.13% to 30.00%**. Its window-boundary traces
match the shipped build. Only one speech fixture changed its ASR request trace: a 1.25-second quiet
final fragment was rejected, with unchanged final text. Eight other speech hypotheses differed despite
matching request traces. Whisper's sampled fallback is a known source of variation, but matching
traces do not prove equivalent native state or establish the cause of a transcript difference. The
raw failure stands; no adjusted score or favorable arm replaces it.

Forty reserved English/Romanian recordings remain untranscribed in this investigation. Their
123 prepared-condition plan was not restored or decoded after calibration failed. No fresh speech,
short-word generalization, paced conversation or all-provider improvement is claimed.

| Build | Executable SHA-256 |
| --- | --- |
| Shipped | `5bbe44eb5f37acf4b6e9701f8f2b7f975f01b39779c54a3b651dcad638e30476` |
| All-window candidate | `e1beec9b65d3897a4ad76db48306e54e26ca291a03f432d868d68ef796875798` |
| Longer-window candidate | `0e6693f8af61cac10482f9070e7684dc4f5fab1a6865df5d210d7f31ee9cbfeb` |

## Independent-noise control

The earlier detector probe used MUSAN, which appears in the conversion's model-card corpus list.
This follow-up instead selected two publisher-described environments from
[DEMAND 1.0](https://zenodo.org/records/1227121): a running washing machine and a running creek.
Credits: Joachim Thiemann, Nobutaka Ito and Emmanuel Vincent; CC BY-SA 3.0. Selection preceded
candidate recognition: channel one, eight-second intervals at 0, 60, 120, 180 and 240 seconds, each
under English and Romanian hints. That yields **ten clips from two scenes, twenty pairs**, not twenty
independent environments.

Range downloads extracted only the required ZIP members. ZIP CRCs were checked, original member
SHA-256 hashes retained, and every prepared clip was hashed and verified by the runner. Published
whole-archive MD5 values are recorded but **were not verified**, since complete archives were not
downloaded. The publisher's environment descriptions are not manual speech-absence annotation.
Using a different corpus also does not establish that the detector never saw it during training.

| Build | Inserted words | Final/draft noise regression checks |
| --- | ---: | --- |
| Shipped | 1 | Baseline |
| All-window candidate | 0 | Pass |
| Longer-window candidate | 0 | Pass |

The three synthetic development sentinels likewise decreased from one inserted word to zero. These
are small suppression controls with little baseline error. They cannot outweigh speech regressions.
Noise-only reports have zero reference words: the scorer's displayed zero WER and zero interval are
not an improvement gate. Its full `gate_passed` remains false; insertion counts and final/draft
regression checks are the relevant noise measures.

ASR request/sample counters exclude detector predictions. No CPU, net work, startup-latency or
device-presentation improvement is inferred from fewer ASR calls.

## Failure paths, review and retention

An initial longer-window executable stopped during preparation: the fixed-shape guard accepted only
Core ML's unspecified shape constraint, while this actual model represents its fixed shape as a
single enumerated alternative. It produced no transcription result. Runtime inspection, a regression
for fixed versus variable enumerations, a real-model preflight and the complete evaluated run confirm
the corrected interface guard. The failed preparation log and source snapshot are retained.

Default tests exercise serialization, active cancellation/reuse, native owner/installation lifetime,
invalid and oversized audio, cancelled/missing preparation, incompatible tensor contracts and exact
short/long policy routing without loading weights. Existing recognition admission, queued
cancellation, dual-source and channel lifecycle coverage runs through the shared implementation.
Review also removed an unused analysis helper and its isolated test; it never participated in the
measured inference path. The unchanged native minimum-length calculation was also centralized;
62 speech tests completed with checked receipts after that cleanup, and the release tool was rebuilt.
The measured snapshots and final-source cleanup record are kept separately.

The reviewed source passed `make check` (**1,278 selected headless tests**, **157 Python checks**),
`make stress` (**456 selected tests**) and `make race-check` (**502 selected tests under Thread
Sanitizer**). Every selected-test run has independently verified discovery/completion receipts. The
package and architecture checkers passed 24 and 103 regression fixtures respectively. Swift formatting
and the final release qualification-tool build passed. No Thread Sanitizer race was reported.

No GUI, live microphone, Zoom/Teams/Meet, native frame timing or performance suite was run. This work
does not close the deferred live-validation requirement or prove absence of every possible crash.

Retained evidence includes acceptance contracts, exact source snapshots, model/input checksums,
selection/preparation code, raw public-corpus outcomes, scores, trace audits, failed preparation and
completion receipts. Disposable audio, research weights and frozen executables are removed only after
checking exact paths and active users. Personal models and Vault data are outside cleanup scope.

Evidence: [checksums and compressed artifacts](data/learned-speech-validation-2026-11-15/checksums.json).
