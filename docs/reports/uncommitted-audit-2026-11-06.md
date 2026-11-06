# Uncommitted changes — follow-up audit

Date: 6 November 2026.

## Scope

Reviewed the current uncommitted changes around setup and companion preferences, Chat/Talk
recovery, conversation browsing and export, clarification tools, search indexing and runtime
admission, retained diagnostics, and benchmark qualification. This was a correctness and lifecycle
review, with particular attention to cancellation, stale completions, user input, and UI consistency.

## Findings fixed

| Finding | User impact | Fix and regression |
| --- | --- | --- |
| A voice provider could cancel a setup preview without the caller cancelling it. The cancellation handler left the preview active. | Audio stayed reserved, preventing another preview or conversation. | A current cancelled preview now enters the existing stop-and-drain path. The regression holds playback shutdown, verifies that audio stays reserved until teardown completes, then retries successfully without displaying a cancellation error. |
| Continue speaking remained available during an active user utterance. | Replay changed the session phase, which could discard incoming transcription and its speech-end event. | Replay admission now requires no active speech or pending listening draft. The regression checks availability before and after a partial transcript, attempts replay, then verifies that the complete user utterance reaches the next reply. Existing explicit replay and empty-interruption tests remain in place. |
| Chat settings actions discarded their requested destination and always opened setup. | Choose a voice / Choose a speech model did not open the named settings page. | Settings navigation now routes those actions directly. A companion-specific reply-model override still opens that companion's profile. The regression checks all three routes, override preservation, and absence of capture or launches. |
| Reading-size changes replaced all native typing attributes. | Newly entered composer text lost its configured ink color. | Typography now updates font and paragraph attributes while retaining other typing attributes. Native editor insertion verifies the resulting text color; selection and input-method composition regressions also run. |

The audio and typography failures were reproduced in failing tests before their production fixes.
The navigation finding was traced through the app's action wiring and covered with a route/recovery
regression. No model-output filters, new dependencies, or performance-budget changes were introduced.

## Validation

Targeted checks passed, including preview cancellation/retry, active-utterance preservation,
speech replay without repeated inference, settings recovery, native text selection, input-method
composition, and reading-size color preservation. Completion is checked against discovered-test
receipts, not process exit alone.

| Check | Result | Evidence |
| --- | --- | --- |
| `make check BUILD_DIR=build/audit-validation` after the product fixes | Passed: 873 selected tests across 20 runs; 112 Python tests; architecture, formatting, localization, benchmark fixtures, packaging, GPU/helper lifecycle and catalog checks. | `build/test-results/run-vtj9tw42/verified.json`; `/tmp/sillies-audit-check.log` |
| `make stress` | Passed: 255 selected tests across 13 runs. | `build/test-results/run-jrm23tiz/verified.json`; `/tmp/sillies-audit-stress.log` |
| `make race-check`, with the refined window fixture | Passed: 303 selected tests across 16 runs, with no race reports. | `/tmp/sillies-audit-race-final.log`; receipt directories below. |
| Final focused regressions, including the refined window fixture | Passed: six selected tests, including six native-window lifecycle cases. | `build/test-results/run-61c2k7b8/verified.json`; `/tmp/sillies-audit-final-focused.log` |

Final instrumented receipts under `build/test-results`: `run-1_evjj5t`, `run-okaov6kc`,
`run-z12foyxb`, `run-ux1d5tdg`, and `run-8ofa_ka6` (each contains `verified.json`).

### Native-window test follow-up

The initial instrumented run timed out waiting for the original window fixture's native identifier
to disappear. It reported no data race. This same intermittent test timeout was recorded in the
earlier setup audit. An isolated rerun and a subsequent full instrumented run passed.

The fixture now owns its `NSWindow` in synchronous methods, explicitly releases it, and verifies
deallocation separately from WindowServer retirement. It exercises six create/destroy lifecycles
without presenting a window. Closing a window and releasing its object are distinct operations in
[AppKit's closing contract](https://developer.apple.com/documentation/appkit/nswindow/close%28%29).
The original two-second deadline is unchanged.

The repeated cases passed normally and under instrumentation. The original fixture did not record
deallocation, so the precise cause of its first timeout cannot be established retrospectively.
This is improved test ownership and diagnosis, not evidence of a production metadata bug or a
guarantee against all future WindowServer delays.

## Limits

Checks run headlessly. Visible window activation/stacking, real permission prompts, physical
microphone input, and audible playback require an explicit interactive check and are not certified
by this audit. No new model-quality benchmark scores are claimed. In particular, the existing
Apple general-knowledge limitation documented in the conversation-usability report remains.

The running app was not restarted or replaced by validation; the validation build uses its own
output directory.
