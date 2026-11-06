# Conversation design and everyday usability — implementation audit

Date: 6 November 2026. Scope: UX-01 through UX-07 from the product opportunities review.

## Experience delivered

| Area | Result |
| --- | --- |
| Shared presentation | Keep the companion header, anchored bubble, existing theme and compact Talk controls. Short recoveries wrap their content; long notices remain bounded. |
| Starting a conversation | Editable ideas for a recording, a saved item, language practice and continuing a topic. An existing draft is never replaced. Setup failures keep their existing settings/recovery actions. |
| Activity | Preparing context, waiting for inference, using a tool, writing, listening and speaking reflect actual session/runtime events. No simulated percentage or reasoning transcript. |
| Clarification | A model can request two or three choices. One completed message owns the question; the user can choose, type, speak or dismiss. Choices preserve an existing typed draft. Closing and reopening preserves pending questions. |
| Navigation | A visible search button and Command-F, relevant search excerpts, indexed date navigation and the existing source cards. Searching and browsing preserve the composer and bounded inference context. |
| Export | A native save sheet and cancellable, paged Markdown export. New messages arriving after export starts, unsent drafts and the separate memory store are excluded. |
| Reading | Shared Small/Standard/Large text preference, saved across launches. Native selection, copy, IME composition and reduced motion are retained. Long questions begin with the question in view; explicit reading is not displaced by arriving text. |
| Recovery | Stopped replies expose Try reply again; incomplete spoken replies expose Continue speaking. Original text and unsent drafts remain available. |

All 22 language catalogs include the new interface copy. Language practice uses the companion's
selected language, with an editable draft before submission.

## Audit findings and corrections

| Finding | Correction / regression |
| --- | --- |
| A late search could replace a newer query or publish after closing. | Independent search and navigation identities, cancellation before reads and before publication, and submitted-query capture. Delayed-result regression preserves the newer result and draft. |
| Cancellation from the repository could appear as an error. | Treat cancellation as cancellation; do not publish a warning. Search and page-cancellation regressions exercise this separately from stale-result rejection. |
| Retry existed in the session but was hidden when stopping did not produce an error. | Include retry/resume availability in notice visibility; inspect stopped-reply previews. |
| Export progress and completion could stall in AppKit's termination loop. | Inject modal-safe delivery, bound progress to one outstanding callback, retain and cancel the writer, and drain it before completing shutdown. A headless modal-run-loop regression verifies completion. |
| An export could otherwise publish deleted history or overwrite its own archive. | Revalidate the conversation generation before atomic publication and reject the SQLite archive, sidecars and directories as destinations. Tests cover clear-during-export and destination protection. |
| A default bottom anchor hid the top of an empty welcome or a tall question. | Empty welcome begins at the top; pending questions have an explicit reading state. User scrolling and selection retain control. |
| Clarification cards could hide preceding explanatory text or replace a selected native text view; choices ignored the larger text preference. | Keep the full message in its existing text view, add choices beneath it and apply the selected size. A regression verifies text-view identity and selection through question arrival. Inspect long localized choices at minimum window size. |
| A native model could continue generating after returning a question. | Exit through Apple's documented tool error boundary, preserve the canonical exchange and streamed text, and discard the interrupted framework session. The next answer starts a normal turn. |
| A downloaded response could include extra calls after a question. | Stop the loop immediately after the accepted question. A regression includes six trailing calls and verifies none is executed or recorded. |
| Restored question data was an untrusted boundary. | Validate question/choice lengths, distinct choices and resolution on decoding. Once answered, dismissed or superseded, a question cannot be reopened by a late callback. |
| A model comparison asserted identical tool sequences. | Keep the matched native control as diagnostic evidence, not an exact-output assertion. Tool selection is not deterministic, and a smoke check is not a quality score. |

## Ownership and resource use

- `ChatSession` owns turn and question transitions. Views forward commands and render typed data.
- `ConversationBrowser` owns search and navigation, separately from recent inference messages.
- `ConversationExport` owns preparation, cancellation, progress and shutdown; the repository reads
  bounded pages and the persistence writer performs file work away from the main actor.
- Date navigation adds an `(owner, created, sequence)` index. A version-four upgrade regression
  verifies existing messages, drafts and handles survive.
- Export captures a maximum saved sequence and yields between pages. A 2,000-message test includes
  a concurrent append and verifies exact exported content. It does not build an archive-sized array.
- Atomic replacement occurs only on success. Cancellation preserves an existing destination and
  removes the temporary file. Earlier-message edits may be reflected during export: it is a
  bounded-sequence export, not a frozen database snapshot.
- Neither clarification nor the interface holds an inference slot while waiting for the user.
  Questions are model-authored typed tool results; no sentence matching or answer-repair filters
  were introduced.

## Validation

Checks use the headless runner and verified completion receipts. They do not infer success from
process exit alone.

| Check | Result | Receipt under `build/test-results/` |
| --- | --- | --- |
| `make check BUILD_DIR=build/conversation-validation` | Passed: 869 tests across 20 runs, formatting/architecture/Python checks, all 1,084 strings across 22 catalogs, benchmark fixtures, packaged helper self-tests, parent-exit checks and catalog validation. | `run-uytta23e` |
| `make stress` | Passed: 252 tests across 13 runs. | `run-w_9as8y8` |
| `make race-check` | Passed: 300 tests across 16 runs, with no race reports. | `run-yksk4vlq`, `run-o71xk_lg`, `run-0r_0mro1`, `run-nw7q61qz`, `run-4eqhra3j` |
| Real Apple clarification smoke check | Passed: one test, 8.74 seconds. Includes a matched general-question control; this is not a model-quality score. | `run-6nptcx32` |
| Focused selection, draft and layout regression check | Passed: seven tests, including native text-view identity and selection while choices arrive. | `run-f26z8b1u` |
| Final layout-policy cleanup | Passed: five layout/selection/recovery tests, `make lint` and a rebuilt validation app after replacing layout literals with named constants; values and behavior are unchanged. | `run-d9cn2zxz` |

Visual previews cover empty starters, clarification, search and stopped replies in light/dark,
including the minimum window size, a long companion name, long French choices and the largest
reading size. They are stored under `build/conversation-previews/`. These are rendered application
views, not generated artwork.

Visible window stacking/activation, native save-sheet interaction, VoiceOver listening and physical
microphone/speaker use require an explicit interactive check and were not run. Existing headless
attachment, input, lifecycle and layout tests provide narrower evidence; they do not establish
flawless behavior on every display or device.

## Native model evidence and limits

A bounded real Apple check used the application's available Vault, conversation, memory and
clarification capabilities. The model produced a valid meeting-choice question, and the turn
completed without waiting for a UI response or exhausting its tool budget.

The matched general-knowledge control revealed an existing limitation: both the configuration
without clarification and the configuration with it searched memories, conversation and Vault for
the tallest-mountain question, then reported no information. That comparison did not demonstrate an
answer-quality improvement or a regression caused by the new tool. An earlier isolated one-tool
experiment also misused the question tool as a quiz; testing only that artificial tool set was not
representative of app composition.

Clarification timing and choice quality still depend on the selected model. The native smoke check
does not certify broad conversational quality. Downloaded-provider loop behavior is covered by
injected-runtime tests; no new downloaded-model quality sweep was run. Published model benchmark
scores and benchmark default tool sets were not changed by this interface work.

See [conversation interface contracts](../contributing/conversation-interface.md) and
[tool integration](../contributing/chat-tools.md) for extension boundaries.
