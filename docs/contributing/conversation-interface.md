# Conversation interface

Chat and Talk share one saved relationship with each companion. Closing a bubble is presentation;
ending Talk owns capture shutdown. The transcript must not switch the session’s mode.

## Ownership

| Responsibility | Owner |
| --- | --- |
| Draft, turn state, question resolution and recovery | `SilliesChat.ChatSession` |
| Search, date navigation and the current archive page | `ConversationBrowser` |
| Export preparation, progress, cancellation and shutdown | `ConversationExport` |
| Page reads and export sequencing | `SilliesVault.ConversationLibrary` |
| Indexed date lookup and atomic file publication | `SilliesPersistence` |
| Markdown formatting and validated question data | `SilliesCore` |
| Native save sheet, anchored bubble and text editing | `SilliesApp` |
| Shared message-size preference | App-owned `ChatReadingPreferences` |

Views forward actions; they must not fetch records, write files or hold inference work. Keep the
existing bubble geometry, theme roles, native text selection, composer and Talk controls.

## Starters and questions

Starters are editable drafts, not hidden model calls. `useSuggestedDraft` refuses to overwrite a
draft; selecting a new idea supersedes a pending clarification. Missing models remain visible through
the shared recovery actions. Do not promise unsupported actions in starter copy.

`request_clarification` returns a validated `ChatClarification` with a question and two or three
choices. The completed assistant message owns it. It can be answered once, dismissed, superseded or
restored on reopening. A choice submits a user message without consuming an existing typed draft;
free text uses the normal composer. Talk also accepts a choice while listening between utterances.
Never parse questions or choices out of generated prose, and never await a person while holding an
inference slot. See [tool contracts](chat-tools.md).

## Navigation and export

Search has its own request identity and cancellation boundary. A stale result cannot replace a newer
query or publish after the view/session closes. Search flushes pending messages first. Date navigation
uses an indexed seek to the first message on or after the selected local day, followed by the existing
bounded page read. It never replaces recent inference history or the composer draft.

Export captures the latest saved sequence, then writes bounded pages through that sequence. Messages
arriving later, drafts and saved memories are excluded. Concurrent edits to earlier messages may be
included: this is a bounded-sequence export, not a frozen database snapshot. A clear/forget operation
that changes the conversation generation invalidates an in-progress export.

The writer publishes by atomic replacement only after completion. Cancellation and failures remove
the temporary file and preserve an existing destination. The archive and its SQLite sidecars cannot
be export destinations. Progress has one outstanding delivery at a time. The app injects modal-safe
delivery; closing/termination cancels and drains export before the history flush completes.

## Reading and validation

Message size is shared across companions and survives restart. Applying it must preserve native
selection and defer font changes during IME composition. New content follows the bottom only while
the user is following and has no selection. Empty conversations start at the top. Earlier messages
and Latest remain conditional on content outside the viewport.

Use headless `ConversationUsabilityTests`, `ConversationExportShutdownTests`,
`ConversationClarificationTests`, `ConversationNavigationExportTests`, the date-migration regression,
and the existing composer/reading/attachment/Talk checks. Inspect opt-in light/dark snapshots at
minimum size and with large text and long choices. Native tool-quality checks remain opt-in and
separate from deterministic lifecycle tests. Visible stacking, native save-sheet interaction and
VoiceOver listening still require an explicitly requested GUI pass.
