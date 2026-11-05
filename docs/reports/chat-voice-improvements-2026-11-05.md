# Chat and voice improvement study — 5 November 2026

Baseline: `7a1c09e9f12316c33b80ef8e6bf0fd227c616920`.

## Registered scope and gates

1. Interruption ownership: reversible output pauses, false-trigger recovery, confirmed-word cancellation,
   and context that distinguishes written text from phrases confirmed played. Preserve source messages,
   bounded queues, recognition finalization and lifecycle cancellation. No keyword list decides whether
   an interruption is meaningful; an empty finalized transcript is the initial false-trigger criterion.
2. Tool completion: reproduce recorded LFM failures and inspect native requests before changing policy.
   Evaluate supported generation controls and a bounded final-answer path. Preserve evidence, write
   receipts and exactly-once effects. Reject fabricated answers and longer retry loops.
3. Turn detection: evaluate local audio endpoint classification against labelled completed/incomplete
   speech, including short utterances and pauses. Keep current VAD fallback unless the candidate improves
   endpoint latency without additional premature commits on the registered sample. No Python or new
   community runtime dependency may ship in the app.
4. Reply policy: pass typed Chat/Talk intent to reasoning. Keep spoken output concise and text usable.
   Experiment with deliberate reasoning only on capable models, with bounded output/context budgets.
   Retain a new inference policy only if task correctness improves without losing passing controls.
5. Explicit memory: a reviewed user-authored fact, saved through the existing provenance/revision
   boundary, visible receipt and Undo. No LLM call or replacement of automatic-memory policy.
6. Spoken-turn measurement: preserve stage boundaries from the last speech sample to device presentation.
   Use bounded headless replay and native probes; distinguish simulated playback from physical output.
   Qualify any scheduling change by model pair, complete answers and playback gaps, not first PCM alone.

Maximum two candidates per model-dependent mechanism. Native inference is serial, supervised by
120-second process deadlines, with a 2,400-second aggregate budget excluding compilation and ordinary
tests. Freeze compared workers, inputs and evaluators; preserve all failures and raw evidence. Existing
public benchmark scores are not updated from this targeted study. Do not run inference concurrently
with builds or performance tests. No personal chats, microphone capture, GUI presentation, app restart
or push is needed. Completion requires headless `make check`, applicable stress checks and TSAN.

Results below distinguish retained application changes from rejected experiments.

## Retained application changes

- A candidate voice interruption pauses the existing output session. Recognized words cancel the
  reply; an empty finalized utterance can resume the same queued audio without another user message.
  Paused output retains its queue bound and suspends the stall watchdog. Mute, stop and finish cancel
  the control task. This is not resumable inference: recognition still preempts active text/synthesis,
  and a playback pause cannot recover a cancelled generation.
- Reply completion and inference preemption no longer overwrite an in-flight microphone finalization.
  Previously, that race could leave the completed correction buffered instead of submitting it.
- Chat and Talk now carry typed presentation intent through history preparation and context budgeting.
  Talk adds explicit spoken-response guidance; ordinary Chat retains its prior wording. Original
  assistant text, message roles and the latest user prompt remain intact. The attempted playback-context
  extensions did not qualify and were removed, as described below.
- **Remember this…** on a user message opens the shared-theme editor. The user reviews a topic and fact,
  then saves through the existing provenance/revision boundary without inference. The source is flushed
  first; successful writes publish the existing receipt and Undo. Duplicate/stale writes retain the
  editable draft and a localized error. All 22 localization catalogs are complete.
- Delivery measurements now share the last VAD-positive frame's host-clock origin through endpoint
  detection, recognition finalization, first text, PCM and device presentation. This is a VAD-frame
  boundary, not an independently measured last phoneme. The generated-answer benchmark uses the
  production conversation service, phrase assembler, registries and bounded silent playback sink.

## Endpoint experiment

The development-only prototype uses the official
[Smart Turn v3.2 checkpoint](https://huggingface.co/pipecat-ai/smart-turn-v3), its
[reference implementation](https://github.com/pipecat-ai/smart-turn), and the published
[labelled test data](https://huggingface.co/datasets/pipecat-ai/smart-turn-data-v3.2-test).
The model is pinned to `f766f81d3cfdf7737ac64aad813d91bbfd56bf93`. The sample is the first two rows
per language and label from the first 100 published rows: 60 clips, comprising 25 completed and
35 incomplete utterances. It is largely synthetic and is not a device or live-conversation test.
The reference preprocessing uses the last eight seconds, normalizes and pads audio, and appends
300 ms of silence. One CPU inference thread is used.

| Completion threshold | Accepted completed utterances | Premature completion on incomplete utterances |
| --- | ---: | ---: |
| 0.5 | 24/25 | 5/35 |
| 0.8 | 24/25 | 1/35 |

Feature extraction plus inference had a median of approximately 35 ms. Both registered thresholds
fail the zero-premature-completion screening gate. The fixed 900 ms VAD was not replayed on these
clips, so this is not a measured head-to-head endpoint-accuracy comparison. **Keep the existing
900 ms VAD endpoint.** No ONNX,
Python or additional model dependency is added to the app. A first prototype attempt used the wrong
scalar extraction for the ONNX return value; the corrected reader uses the same rows and model,
with the initial failed attempt preserved.

## Reply context and reasoning policy

The first playback-context candidate placed delivery JSON in the historical assistant message.
Apple copied that format into its answer. It was rejected. The second candidate keeps original
assistant text and places clearly labelled playback facts in earlier user-role source context.
Its initial six cases pass structural/lexical checks on Apple, Qwen 3.5 4B and LFM 2.5 24B (18/18).
However, the continuation prompt itself said which step the user had heard. That does not establish
that the model interprets playback metadata correctly.

Two harder held-out cases instead ask only to continue, after either the first spoken step or no
spoken words. **The candidate correctly resumes the sequence in only one of six observations**
(implementing-agent review): LFM restarts from the beginning when nothing was played. In the other
cases, models skip unheard instructions or misidentify the interruption point. The baseline also
misses all six. Both arms nevertheless pass five of six lexical/structural case checks because
mentioning tea leaves does not prove correct ordering. These false positives are preserved, not
rescored into success. **Neither playback-context representation is retained.** Existing archive
delivery metadata and the prior interrupted-reply notice remain; precise last-heard continuation
has not been solved. The two-candidate limit was reached.

Typed Chat/Talk intent is retained independently. It provides modest spoken-response guidance,
not a promise of factual accuracy, plain-text formatting or a hard spoken-length cap.

Granite 4.2 3B's publisher template defaults to thinking when `enable_thinking` is absent. The isolated
experiment enables that default and reserves 1,024 reasoning tokens, preserving the other settings.
Across two seeds, both baseline and candidate pass 3/6 cases per pass. The candidate introduces
reasoning-token-limit failures. Its apparent identity improvement is formatting only: baseline
"I'm Pogo" was already correct but failed a name-only check. Neither arm reliably creates/corrects
persisted memories in these cases. **Do not enable this thinking policy.** This is a bounded test of
one configuration, not a claim that every reasoning budget or model behaves identically.

## LFM completion experiments

Two bounded alternatives were evaluated; neither is retained.

1. **Native tool-opener suppression after the allowance is exhausted.** The eight-case screen gave
   15/16 passing case observations for both baseline and candidate across two seeds. Replaying four
   identical saved terminal requests then exposed the tradeoff: the baseline made another attempted
   call in two requests, while suppression replaced those with an invalid reasoning boundary and a
   reasoning-token-limit failure. Preventing an opener did not produce a reliable final answer.
2. **One independent answer from completed tool evidence.** A prototype completed all four saved
   requests without further calls. The production-loop comparison did not hold up: the native arm
   passed 7/8 cases in each seed; the composition arm passed 6/8 in each. In one matched record-detail
   task, both arms retrieved the requested identifier, but composition exhausted its reasoning budget
   instead of answering. Another completion ran out of tokens after an empty search. Source-selection
   mistakes also occurred before the terminal policy was reached; those cannot be attributed to it.

The second comparison uses the same new worker and changes only the isolated catalog's terminal
policy. It includes the first Chat-style candidate, so its absolute counts are not interchangeable
with the first comparison's committed-baseline counts. Final application Chat wording is restored to
its previous value; the more verbose style did not establish an agent-task quality gain. Talk guidance
is a separate retained change; playback-context metadata was subsequently rejected.

Tool outputs, argument/result pairing, native templates, private reasoning boundaries, stop reasons
and token budgets were inspected. Three native renderings of an identical saved request produced
identical token fingerprints; this did not explain all variation between independent runs. Seeded
sampling does not justify assuming every whole-loop run is identical. The failures remain integration
observations, not a blanket claim about the model's capabilities. No token blacklist, guessed call,
answer filter, extra retry loop or new terminal-policy abstraction remains in the product.

Existing loop regressions cover published text, refusal results, unchanged execution allowances
through recovery, and reuse of completed operations. They do not claim that every model will choose
an appropriate tool or give a factual answer.

## Generated-answer speech timing

The probe generates the same three-sentence rainbow explanation with Qwen 3.5 4B and feeds actual
streamed output through the production phrase assembler and voice registry. It compares the current
350 ms opening-phrase deadline with 120 ms. The deadline is a maximum wait, not an enforced delay:
punctuation and existing phrase rules can release text earlier. Playback is a bounded, silent sink
paced at audio duration. No microphone, STT or physical output device is part of this measurement.

| Voice model | Warm first PCM, current | Warm first PCM, earlier | Difference | Simulated gap, current → earlier |
| --- | ---: | ---: | ---: | ---: |
| Kokoro 82M | 733 ms | 654 ms | 79 ms | 0 → 0 ms |
| Pocket TTS | 694 ms | 630 ms | 64 ms | 0 → 0 ms |
| Qwen3-TTS 0.6B | 725 ms | 650 ms | 75 ms | 33 → 31 ms |

Each cell is a median of only two warm observations per arm, on the same M4 Pro with 48 GiB and
macOS 26.7.2 (25G332). Every observation delivered all 54 generated words exactly once. First text
was approximately 434–443 ms and complete text 1.22–1.27 seconds; these are post-request timings.
First non-silent PCM was within about 3 ms of first PCM. Neither is measured audible presentation.

Kokoro and Pocket completed warmup plus alternating pairs within a process. Qwen's roughly
26-second audio made that five-observation design exceed the 120-second process limit. Its qualified
comparison uses two smaller processes, each with a discarded warmup and one pair, in reversed order.
Incomplete earlier runs are retained as failures and excluded from the balanced table, according to
the recorded batching amendment. Kokoro's initial Core ML preparation also exceeded the original
batch deadline; its subsequent complete comparison is explicitly warm, not a cold-start claim.

The initial temporary voice store had missing receipts and artifacts. Kokoro and Pocket were restored
from intact local model installations into the isolated test store; Qwen was downloaded from its pinned
manifest. Fish's large weight download did not complete in two 180-second attempts. **There is no new
Fish result.** Model downloads are recorded separately from inference; app selections were untouched.

**Keep the current 350 ms policy.** Smaller first phrases produced modest timing gains, but audible
prosody was not reviewed, only one synthetic answer was measured, and one voice family was unavailable.
The new probe makes a future broader comparison possible without presenting synthetic timings as
whole-conversation responsiveness. The app's new host-clock instrumentation separately captures
endpoint delay, recognition finalization and actual device presentation.

## Evidence and validation

All 44 native execution attempts are retained, including setup errors and timeouts. Recorded execution
was 1,810 seconds against the 2,400-second cap. Candidate exhaustion is a stop condition; rejected
prompt, token-selection and terminal-completion experiments do not remain as unused product layers.

The [evidence archive](data/chat-voice-2026-11-05/raw-evidence.json.gz) contains frozen corpora,
evaluator code, inputs, outputs, tool calls, persisted-state receipts, model/runtime fingerprints,
prototype source overlays and execution logs. Weights, binaries and audio are represented by hashes.
Expiring signed dataset URL queries are omitted; stable dataset revisions, row IDs and audio hashes
remain. The [computed results](data/chat-voice-2026-11-05/results.json.gz) keep automatic checks apart
from the [implementing-agent reviews](data/chat-voice-2026-11-05/manual-review.json.gz).
There was no independent human review.

Run the standard-library-only audit without models or network access:

```sh
python3 docs/reports/data/chat-voice-2026-11-05/audit.py
```

It verifies artifact hashes, frozen corpus/job identities, reply and evidence hashes, recomputes
automatic checks, validates review bindings and the native-execution budget, and rebuilds the tables.
Its negative controls reject altered responses/scores and incomplete or duplicated speech delivery.

| Application validation | Result |
| --- | --- |
| `make check` on final source | Passed: 763 selected Swift/XCTest tests, 102 Python tests, formatting, architecture, 74 benchmark fixtures, 947 localized strings, native helper self-checks and parent-exit checks |
| `make stress` | Passed: 183 selected tests with bounded execution |
| `make race-check` | Passed: 221 selected tests across lifecycle, playback, device-rate and echo groups |
| Final playback TSAN verification | Passed: all 14 playback tests rebuilt after the final watchdog cancellation recheck |
| Study audit | Passed: 30 Chat runs, three voice comparisons, 60 endpoint clips, 20 focused reviews and all 44 native execution receipts; six negative controls rejected |

Stress and the full TSAN suite preceded the final watchdog recheck; instrumented playback was rerun
afterward, followed by the final full `make check`. Raw discovery inventories, completion events and
verified test receipts are included in the evidence archive. The memory editor was rendered and
inspected in both light and dark themes; save/provenance/Undo uses temporary persistent storage.

All checks were headless. No visible-window, live-microphone or physical-audibility qualification was
run. No app settings were changed, and the running app was not restarted. The new build is isolated
at `build/chat-voice-2026-11-05/validation/Sillies.app`.
