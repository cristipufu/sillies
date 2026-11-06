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
| In-bubble utility navigation | `ChatWindowNavigation`, owned by `ChatSessionWindowController` |
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

## Explicit context and memories

The paperclip opens a bounded Vault picker. Vault rows can also be dragged into Chat, or opened with
**Discuss with…**. `ChatSelectedRecords` owns at most three stable record IDs; the checkpoint saves
those IDs alongside the draft. Removing a chip stops automatic inclusion in future turns. Earlier
messages may still quote the item. A selected item is context, not a restriction on other available
search tools. This is text/OCR context, not image interpretation.

`ConversationMaterialProviding` resolves current record data on the Vault actor for every reply.
Deleted items remain visible as unavailable references and supply no evidence. Excerpt selection uses
the actual excerpt budget; do not select a large passage and then cut off its relevant detail.
`read_vault_record` can read the selected ID when a bounded excerpt is insufficient. Never persist
full selected bodies in the checkpoint or load them on the main actor.

Memories has three pages: **Pinned**, **Learned**, and **Manage**. Pinned facts are user-authored,
separate from model-written memories and from companion identity. Four shared facts and four facts
per companion fit a small explicit profile. A companion-specific topic supersedes the same shared
topic. Edits use revisions; models have no capability to change this profile. Learned-memory search
retains provenance, correction and Undo. Late search results cannot replace a newer query.

`ConversationBackgroundAccess` injects selected evidence and the applicable profile into bounded
reply preparation. Values are quoted source data in a user message, never developer instructions.
Preparation respects the chosen model's budget: reduce old history first, then excerpt payloads,
then whole lowest-priority pinned facts if necessary. Never truncate a fact mid-sentence. Reply
details disclose included and omitted counts. The full archive and profile remain intact.

Message deletion, learned-memory deletion, and companion-preference reset have separate controls.
Deleting messages can leave a memory's original source quote available; forgetting a memory can
leave its original messages searchable. Neither removes pinned facts. These operations invalidate
conversation generations, checkpoints and derived search work as appropriate. Native and downloaded
prefix caches also compare history/profile revisions before reuse.

Storage mutations accepted by `ChatPersistenceOperation` outlive presentation dismissal and drain using
the injected modal-safe delivery path before app termination. A late completion must not restart a
finished conversation. Storage ownership remains in the repository actor; presentation owners do
not create live repositories or perform inference.

## Navigation and export

Memories, conversation search, the Vault picker and the memory editor occupy the existing anchored
Chat bubble. Do not present these routine pages as native sheets over its transparent, shaped window:
macOS sheet dimming applies to the parent window, not just the drawn bubble. Use the shared Back
header for utility pages; memory editing retains explicit Cancel and Save actions.

Keep the conversation mounted while a utility page is visible so its viewport, draft and native
selection survive. Conceal its native text views and release their first responder through
`NativeTextVisibility`; SwiftUI opacity and hit testing alone do not prevent keyboard interaction.
Keep the session's availability task on the stable root. Navigating pages must not restart inference,
switch Chat/Talk, or stop capture. Outside-click dismissal is suspended during a utility task, as it
was for the native sheet, and resumes on return to the conversation. Export file choosers and
destructive confirmations remain separate, explicitly scoped modal actions.

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

Use headless `ChatPageNavigationTests`, `ConversationUsabilityTests`, `ConversationExportShutdownTests`,
`ConversationClarificationTests`, `ConversationNavigationExportTests`, the date-migration regression,
and the existing composer/reading/attachment/Talk checks. Inspect opt-in light/dark snapshots at
minimum size and with large text and long choices. Native tool-quality checks remain opt-in and
separate from deterministic lifecycle tests. Visible stacking, native save-sheet interaction and
VoiceOver listening still require an explicitly requested GUI pass.
