# Talk controls and spoken replies — November 5, 2026

Talk uses compact controls inside the shared thought bubble beside the mascot. Starting it never
opens a Chat window first. The transcript action opens the same conversation read-only without
switching modes or stopping capture; dismissing it also leaves Talk running. Explicit Chat selection
still switches modes and restores the draft. Shared notices expose model setup and failure recovery;
the bubble follows the companion's placement and native window level. Chat keeps its selectable
message view, with clearer body typography and a single expanding message composer.

The reported raw `Swift.CancellationError` could reach the UI because voice generation previously
wrapped every thrown error as a synthesis failure. Recognition can preempt synthesis during a
normal spoken turn. Expected cancellation now follows interruption/recovery transitions; other
failures retain their typed recovery actions. Cmd-C uses the ordinary native copy responder action
and has no cancellation call. The exact cause of the reported incident is unknown: that running
app's standard output and error streams pointed to `/dev/null`. This change does not add retained
diagnostic logging.

**Continue speaking** replays already generated text after its confirmed spoken prefix, without
inference, tools or another stored message. Fresh attempt identities reject stale callbacks. A
reply or replay waits asynchronously for the preceding playback stop. A regression deliberately
holds that stop unfinished and requests continuation immediately; the next playback cannot begin
until teardown completes. Phrase-boundary receipts mean a partly heard phrase can repeat.

## Spoken-style check

The production prompt now requests natural sentences without lists, Markdown or visual references.
It also distinguishes conversational assistance from actions supported by installed tools. No
generated-text filter, sampling change or case-specific instruction was added.

One candidate was evaluated against the previous frozen worker: three synthetic questions, two
repeats, Apple and Qwen 3.5 4B, using the production five-tool profile. The questions cover capabilities,
instructions and a general explanation. All **24 turns** completed in **97.4 seconds** of a registered
600-second process budget. No further candidates were fitted to these questions. The builds are
not a controlled latency comparison, and this small screen does not update the public leaderboard.

| Model | Baseline automatic checks | Candidate automatic checks | Inspection of generated answers |
| --- | ---: | ---: | --- |
| Qwen 3.5 4B | 4/6 | 6/6 | Two baseline replies used Markdown lists; all candidate replies used spoken prose. |
| Apple | 0/6 | 0/6 | Both prompts unnecessarily searched private sources for general questions. Plain prose alone did not make the answers useful. |

These counts are not semantic quality scores. Baseline Qwen's tea reply passed despite putting
steeping before pouring. The candidate still included imprecise water-temperature wording in one
repeat and an unexplained water quantity in another. Independent human and auditory review remain
outstanding. The registered goal of useful spoken answers from **both** models was not achieved.

Apple's native adapter was inspected for forced tool selection and malformed role handling: it
registers tools and preserves native transcript roles without requiring a tool call. The application
currently uses greedy generation for Apple's tool-bearing requests. This screen does not isolate
that sampling policy, the remaining prompt, tool descriptions or model behavior. The private-source
mistake already occurs with the baseline; its root cause remains unresolved. It must not be described
as a new prose-formatting regression or proof that the model alone is at fault.

The [baseline evidence](data/talk-spoken-style-baseline-2026-11-05.json.gz) and
[candidate evidence](data/talk-spoken-style-candidate-2026-11-05.json.gz) contain the frozen corpus,
requests, calls, replies, checks and binary hashes. Both passed the independent archive audit,
reproducing their recorded checks and metrics. This establishes evidence integrity, not answer
correctness. The [study record](data/talk-spoken-style-2026-11-05.json) preserves the predeclared plan,
process ledger and audit results.

## Validation

The full headless check passed with 784 Swift tests across 19 runs and 105 Python tests, including
architecture, localization, catalog and helper checks. The stress run completed 189 tests across
11 runs. The additional delayed-stop regression and Talk presentation tests passed in a seven-test
targeted run after the initial full check. Receipts verify discovered-test completion.
The complete Thread Sanitizer run then passed 237 tests across 14 runs, including the delayed-stop
regression and acoustic-delay/device-rate matrices, with no reported races.

Native text-selection copying during streaming, preserved reading position, no Chat window on Talk
startup, mode-switch draft retention, replay identity and cancellation are covered. Light and dark
HUD snapshots use the headless renderer. Visible activation/stacking tests and physical microphone
or speaker checks were not run. The app was built in an isolated directory; the user's running app
was not replaced or restarted. Logs are in `build/talk-controls-2026-11-05/`.
The final five-test presentation/continuation run passed after the view cleanup; light and dark
startup and missing-model HUD snapshots were inspected. Long setup messages truncate in the bar
and remain available through its details control.

The later Chat/Talk presentation follow-up passed `make check` with verified completion of 820 Swift
tests across 20 runs and 112 Python checks. Capture regressions open and dismiss the transcript between
successive spoken turns, verify that the device stays live, and check that explicit Chat selection and
End voice still release it. Transcript refreshes no longer supersede Talk's startup readiness checks.
Native layout tests cover the compact bubble's level and cached sizing, expanding drafts, input-method
composition, and curved Chat tails on every edge. Light/dark previews are in `build/chat-design-previews/`.
The signed release build was installed at `build/Sillies.app` and the local app restarted after validation.
Visible stacking and physical microphone/speaker checks remain unrun.
