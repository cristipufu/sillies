# Chat and voice follow-up — November 5, 2026

This follows [the earlier bounded study](chat-voice-improvements-2026-11-05.md), based on
`3efcafbf1da51037646c9645bfb9550720d37e46`. The product changes address interruption recovery
and direct memory correction. The opening-phrase default stays at **350 ms**. These measurements
do not update the full model leaderboard.

The subsequent [Talk controls and spoken-style check](talk-controls-2026-11-05.md) adds the compact
voice HUD, explicit playback continuation and a bounded native prompt comparison. Its narrow
formatting results remain separate from the timing experiment below.

## Product changes

An empty recognized interruption resumes paused playback. If recognition has already preempted
inference, Chat re-synthesizes only retained, generated phrases after the last confirmed playback
boundary. It keeps the same reply and never repeats reasoning, searches or memory writes.
Unfinished text is not invented or completed by a second inference call. A partly heard phrase may
repeat because playback confirmation is at phrase boundaries, not individual words. If nothing
recoverable was generated, Chat returns to listening with the available written response preserved.

Playback progress is recorded before asynchronous UI notification. Separate attempt identities
reject old callbacks after recovery. Real words, stop and conversation teardown cancel recovery.
The tests cover preemption before speech detection, during recognition, after an empty result,
audio-only preemption, stale callbacks and teardown during replay.

Review also found that recognition completion could overtake its asynchronous release of inference
admission. Channel finalization now joins the same release task used by cancellation, and scheduled
recognition releases admission before returning either a result or an error. A gated regression
holds release unfinished to verify that completion cannot race ahead; a late cancellation must not
release the next turn's reservation. No wait blocks the main actor or the audio callback.

Memories now offer **Edit**, using the existing themed editor. Corrections bypass inference,
validate the memory revision atomically, retain the original message, and display **Edited by you**.
The changed fact, search index, Undo receipt and invalidation of obsolete context commit together.
The model receives the edited value as the user's statement; the old quote is not represented as
support for the correction. A separate editing capability prevents model-authored writes from
claiming manual-correction provenance. New copy is translated into all 22 supported UI languages.

## Voice startup experiment

One warmup and a current/early pair were planned in each process, with reversed order in a second
process. Qwen 3.5 4B generated replies through the production conversation service. The actual
voice providers consumed production phrase assembly. A silent playback-rate sink collected WAVs;
it did not open speakers or the microphone. Inputs covered numbers, a URL and identifier, French,
German and a longer answer. All inputs and output artifacts are synthetic.

Median **first non-silent PCM from reply request**, in milliseconds:

| Voice | Scenario | 350 ms opening | 120 ms opening | Complete processes |
| --- | --- | ---: | ---: | ---: |
| Kokoro 82M | English numbers, URL, identifier | 783 | 755 | 2/2 |
| Pocket TTS | English numbers, URL, identifier | 792 | 702 | 2/2 |
| Qwen3-TTS 0.6B | English numbers, URL, identifier | 791 | 711 | 2/2 |
| Qwen3-TTS 0.6B | French numbers | 760 | 665 | 2/2 |
| Qwen3-TTS 0.6B | German explanation | 665 | 699 | 2/2 |
| Qwen3-TTS 0.6B | Longer English answer | 802* | 633* | 0/2 |
| Fish S2 Pro | English numbers, URL, identifier | 1,105 | 1,016 | 2/2 |

Complete rows have only **two warm observations per arm**. Kokoro's individual runs moved in
opposite directions. German was slower with the earlier deadline. This is exploratory evidence,
not a statistically reliable or universal improvement. Generated wording can differ between arms;
these are complete-pipeline comparisons, not controlled pronunciation comparisons of identical PCM.

\* Each long-answer process reached its 110-second execution deadline before its third observation.
The table retains the one completed warm observation per arm; neither constitutes a completed pair.
The current warm answer contained 59 words and 42.8 seconds of generated audio, completing in
42.94 seconds. The earlier-deadline warm answer contained 93 words and 53.76 seconds of audio,
completing in 53.70 seconds. Measured simulated playback gaps were 59 ms and 33 ms respectively.
Those durations primarily reflect the generated speech length and paced playback, not demonstrated
42–54 second inference stalls. The model's text arrived much earlier. These timeouts are experiment process limits,
not observed application turn failures. They do not qualify the earlier deadline.

Fish's original two download attempts were terminated by the study supervisor after 170 seconds
each. The CLI discarded progress and process termination bypassed cancellation cleanup. Those
attempts established a setup-deadline failure, not a Hugging Face outage or model failure.

The subsequent installer fix prints byte/verification progress, handles SIGINT and SIGTERM through
cooperative cancellation, and separates its configurable 30-minute setup deadline from inference
limits. On the real Fish transfer, SIGINT produced exit 130 after saving a 32,194,063-byte resume
checkpoint. Rerunning the command completed setup in about 442 seconds; all six artifacts, totaling
6,731,364,235 bytes, passed size and SHA-256 verification. This setup reused the previously downloaded
codec and configuration. The loopback regression now requires a nonzero HTTP Range offset, so a
complete restart cannot pass as a resumed transfer. The original failed setup attempts remain in
the evidence, alongside the separately authorized follow-up.

Both Fish inference processes then completed using the original frozen benchmark and helper
binaries, taking 60.0 and 51.8 seconds. Warm first PCM improved from 1,129 to 976 ms in one order,
and from 1,082 to 1,057 ms in the reversed order. The median improvement is approximately **89 ms**.
There are only two warm observations per setting. The early setting ended its first phrase at
“The appointment is at”; the current setting included the time and date. That boundary needs
listening review before treating the small latency gain as a better experience. The 350 ms
product default remains unchanged.

The 14 native processes consumed **919.8 seconds** of the registered 1,800-second inference budget.
The original download attempts consumed 340.0 seconds of their separate 360-second budget; the
authorized installer follow-up has its own setup plan. All completed and timed-out inference runs,
original unavailable entries and installation evidence remain in the
[compressed evidence](data/chat-voice-followup-2026-11-05.json.gz).
It includes the plan, revisions, frozen-file hashes, raw observations, execution status and WAV hashes.

The audit checks exact ordered text delivery, PCM chunk/sample totals, and WAV channel count,
sample rate and frame count. These checks do **not** prove correct pronunciation or pleasant phrasing.
WAVs remain available under `build/chat-voice-followup-2026-11-05/` for listening. Auditory quality
review and physical-device latency remain unmeasured, so the product timing does not change.
The frozen probe's overall audio elapsed time includes WAV serialization; its first-PCM timestamp
is captured before that I/O. The checked-in probe now snapshots elapsed time before artifact writing.

## Repeatable verification

The new short flow check feeds synthetic PCM through the actual capture queue, echo cancellation,
VAD, recognizer finalization, conversation service, tool execution and speech phrase delivery.
Scripted recognition and reasoning make consecutive turns and corrections reproducible without
loading models or collecting microphone input. This checks orchestration, not ASR accuracy or
physical acoustics. The native TTS experiment above exercises actual synthesis separately.

A brief optional device check remains useful: start Talk, let one phrase play, make a noise that
produces no recognized words, interrupt with real words, then switch output once and continue.
Confirm recovery, one copy of the new utterance and no speech from an old attempt. Keep this bounded
to a minute; do not run an unattended soak. Device-route changes cannot be certified by a silent
sink. Apple's [playback-completion contract](https://developer.apple.com/documentation/avfaudio/avaudioplayernodecompletioncallbacktype/dataplayedback)
is the boundary used by the production playback adapter.

## Benchmark coverage

Six scenarios join the regular corpus: four spoken-continuity cases and two evidence cases.
The corpus is now **80 scenarios, 99 profile cases and 142 turns per model**; the primary app
profile has 115 turns. Earlier leaderboard scores remain attached to their original corpus.

Two tea cases promote known held-out failures; they are not newly held-out evidence. Two
letter-only variants independently test the next unheard step. Free-form responses require
review of the first instruction and step order. A reply containing all expected words can still
fail that review. Other cases cover a single empty search followed by general knowledge, and
the distinction between a saved plan and evidence of completion.

`source_equals` rejects missing evidence, extra IDs and duplicate IDs. `tool_calls_at_most` counts
all attempts, including repeated or failed calls. Negative controls exercise these rules, missing
results and lexical false positives. Gold checks and rubrics never enter model requests.

## Repository validation

All required checks passed after the recognition-release fix:

| Check | Verified result |
| --- | --- |
| `make check` | 779 Swift tests across 19 runs; 105 Python tests; architecture, localization, catalog, native-helper and benchmark fixture checks |
| `make stress` | 188 tests across 11 runs |
| `make race-check` | 235 tests across 14 runs under Thread Sanitizer; no reported races |

Test completion was checked against the discovered-test receipts, not process exit alone. The
logs, receipt references and their hashes are in `build/chat-voice-followup-2026-11-05/verification.json`.
The full check built an isolated signed app under that directory; the running local app was not
restarted or replaced. GUI checks were not run. Light and dark memory-editor snapshots were
reviewed through the headless renderer. Physical-device listening and pronunciation remain outside
this validation, as described above.

The installer follow-up reran `make check` successfully (779 Swift tests and 105 Python tests).
All four real-URLSession download tests and the extended installation self-check also passed under
Thread Sanitizer. The latter covers successful completion, invalid deadlines, SIGINT, SIGTERM,
deadline cancellation and parent-task cancellation, including cleanup before returning.
These targeted checks supplement the earlier complete Chat/memory stress and race runs. Their
logs are under `build/chat-voice-followup-2026-11-05/fish-download-fix/`.
