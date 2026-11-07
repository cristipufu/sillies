# Vault UX audit — November 7, 2026

The first workspace build had real navigation and layout defects. This pass reviews the page structure,
empty and populated states, asynchronous navigation, compact layouts, action hierarchy and storage controls.
It uses disposable data and native offscreen rendering; it does not inspect personal content.

## Findings and changes

| Area | Finding | Correction |
| --- | --- | --- |
| Page ownership | The library section, Storage and creation/quotation forms had independent state. A sidebar click could leave a form or Storage in front. | The workspace owns one typed page. Sidebar, toolbar and external links use its navigation methods. |
| Sidebar selection | Trash or another section could remain highlighted alongside Storage. | One derived selection follows the active page; forms do not pretend to be a library section. |
| Back and forward | History remembered document IDs but not their sections or filters. | Bounded checkpoints restore the page, query, reading position and composition draft together. |
| Compact navigation | Choosing the already-selected section did not change its value, so the compact sidebar could stay open. Storage disabled the toolbar, including the sidebar button. | Every navigation transition has an identity. The compact sidebar dismisses on transitions, and its button remains available. |
| Stale detail | Changing sections could leave the previous document visible beneath an unrelated heading. | Section changes clear visible selection and cancel pending loads while preserving recoverable edits. |
| Search from other pages | An already-focused search field could change the query while leaving Storage or a form displayed. | Typing, clearing, choosing a match mode and Cmd-F explicitly route to results; programmatic history restoration does not. |
| Returning to a document | Leaving during its initial read could cancel the load without restarting it on return. | Hidden pages suspend the document's owned work. Returning to the library resumes the selected document and its reading position. |
| Late creation | A completed save could navigate away from a page selected while that save was pending. | New-note and composition completion validate the initiating page before changing navigation. The saved result remains durable. |
| Empty list | The entire result column contracted around its placeholder, placing the header halfway down the window. | The column and placeholder fill the available height; the header stays at the top. Smaller typography gives the list and document distinct emphasis. |
| Pagination | Empty and single-page lists showed a meaningless “Page 1” footer. Conversation readers reserved empty footer space. | Page controls appear only when an earlier/later page exists; batch actions remain available for multiple selections. |
| Storage structure | Separately padded, fixed-width views looked like an embedded modal dialog. | A dedicated workspace page uses one content width and aligned sections for usage, export/backup and retention. |
| Storage controls | Unchanged settings still showed Save/Cancel; destructive actions looked like ordinary actions. | Save/Cancel appear for a changed retention choice. Deletion has separate placement, destructive styling and confirmation. |
| Storage accuracy | Directory URL spelling could classify database bytes as search-cache bytes. Conversation storage could appear as capture attachments. | Classification compares normalized paths and distinguishes the separate conversation database. |
| Conversation browsing | The list used an oversized heading and oversized cards relative to other sections. The unselected reader was blank. | List typography and insets match capture browsing; the reader explains how to select a conversation. |
| Interrupted conversation opening | Leaving before the first page arrived could retain a selected companion with an empty reader on return. | Resuming restarts an unfinished initial read, including its requested message anchor; completed pages remain retained. |
| Retention loading | A retention value loaded after presentation could leave the picker showing its initial default. | The picker follows the persisted policy until the user changes it and stays disabled until storage is ready. |
| Creation forms | Native gray actions differed from the app's other primary/secondary actions. Fields could accept edits after a save captured its input. | Cancel and Save use the shared Sillies button styles; action rows remain outside the scrolling fields. Fields are disabled while their save is pending. |
| Review fixtures | Some screenshots captured the first loading frame rather than loaded content. | Settled rendering yields to asynchronous view tasks before capturing; initial/loading states remain separately meaningful. |

## Second pass: everyday use and failure recovery

The follow-up examines actions during navigation, keyboard text selection, empty categories, filtered
results, recording controls and recoverable failures. It keeps persistence and asynchronous transitions
in their owning models; views forward commands with the identity of the item the user acted on.

| Finding | Change | Regression coverage |
| --- | --- | --- |
| An asynchronous Trash action could read the newly selected document after waiting for saves. | Document edits carry their original record ID and revalidate the document generation across waits. Section transitions also have request identities. | Delayed Trash/star actions after switching documents leave both records intact. |
| Audio-follow and bookmark actions could resume against a different recording. | The document owns the follow transition, and bookmark creation carries the clicked record ID and playback position. | A late action from the previous record cannot start following or add a bookmark to the new record. |
| Bulk selection could remain actionable after the search changed. | Actions require the current applied query and visible IDs. Refresh removes selections that no longer belong to the page. | Changing the query disables bulk actions before the replacement results arrive. |
| Native selection ranges were trusted before NSString/AppKit operations. | One checked range policy handles negative, sentinel and overflowing ranges; restored positions reject nonfinite coordinates. | Invalid native ranges are rejected before copy, formatting or editing; valid Unicode selection still works. |
| Draft recovery could publish a late result into a newly opened editor. | Recovery has explicit ownership, disables competing edits and validates the editor request after I/O. | Existing conflict/recovery/navigation tests run alongside the new selection and delayed-action checks. |
| Discussion failures were stored but not displayed. | The workspace status area shows the shared failure presentation with an explicit dismissal action. | An injected discussion failure is visible at minimum size. |
| The redesigned document menu omitted the existing paste-back action for captured items. | The menu again offers Paste into the captured destination. The action flushes current edits, reads the requested record off the UI thread, revalidates its destination and cancels when the Vault closes. | Closing and reopening during the record read cannot continue an old paste or display its failure. |
| Export/backup feedback disappeared too quickly to read; ongoing file work lacked a cancel action. | File feedback remains until dismissed. Cancel invalidates the request and keeps new file operations disabled until the owned worker has stopped. | Obsolete export/cancellation completions cannot finish a newer request; current feedback survives the transient-notice interval. |
| A conversation read failure had no useful retry path. | Retry repeats the failed page or original message anchor while retaining the visible page. | Injected initial-read and page-read failures recover without losing the previous content. |
| Collapsed filters were easy to overlook, and empty categories shared generic copy. | The filter button shows an active count; Clear filters is available inside the filter area and filtered empty states. Empty categories explain what belongs there. | Every category renders at minimum size; filter counts and reset behavior are asserted. |
| Empty lists and readers repeated the same creation action; Trash invited note creation. | The empty reader owns the note-creation action. Trash instead explains restoring and deleting items. | Empty All items, Notes and Trash appear in the compact category fixtures. |
| Empty collection/search names or links could be submitted. | Save remains disabled until the required input is present; Escape cancels and Cmd-Return saves. | Blank and whitespace-only inputs cannot start a save. |
| Long errors could consume the reading area. | Shared bounded notice presentation allows long diagnostics to scroll without expanding the entire workspace. Playback and recording errors use the same document notice area. | Native editor viewport checks require at least 120 pt of reading height in rendered document fixtures. |

The fixtures include light/dark layouts, very long source names and diagnostics, populated recordings,
file references, every empty category, filters, creation, storage and conversation history. They use
synthetic data and do not capture the user's Vault.

## Reviewed surfaces

| Surface | Review |
| --- | --- |
| Library | Empty, one-record note, date groups, selected item, no unnecessary page footer |
| Search | Shared toolbar, date range and source filters, previous-result notice, cancellation ownership |
| Document | Editable title/tags, section selector, notes formatting, native reading area, recovery/failure presentation |
| Recording | Transcript, inline playback, follow controls, bookmarks and file actions at minimum size |
| Links and files | Link composer with fixed actions, preview fallback, external-file explanation and relink actions |
| Collections and saved searches | Enter/leave creation, switch from Storage, restore prior drafts through history |
| Conversations | Empty reader guidance, companion list, selected conversation, conditional history paging |
| Storage | Usage, export/backup/restore, retention and deletion; wide/compact, light/dark |
| Navigation | Every sidebar scope, same-scope return, Storage, forms, collection and saved query; back/forward and late document loads |

## Validation

`VaultWorkspaceNavigationTests` exercises the reported transitions, draft/query restoration, cancelled
selection and empty-column expansion. `VaultWorkspaceExperienceTests` covers native editing, undo/redo,
recovery, source links, reading position, loaded layouts and modal-safe saving. Storage classification
has a separate persistence regression.

Generate offscreen previews without presenting test windows:

```sh
SILLIES_SKILL_UI_SNAPSHOTS=1 bash scripts/test.sh \
  --filter 'vaultWorkspace|vaultSidebar|vaultBackAndForward|vaultEmptyWorkspace|vaultLateDocument|vaultSearchReturns|vaultReturningToLibrary|vaultRecordingAndFile|vaultConversationFiltering'
```

Files named `sillies-vault-*.png` are written into the system temporary directory. The local review copies
live in `build/vault-ui-review`. Rendering allows asynchronous work to advance, but a screenshot delay
is not a readiness assertion or a performance measurement; functional tests assert the loaded state.

The second pass ran this command against the final source:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
SILLIES_SKILL_UI_SNAPSHOTS=1 \
make check BUILD_DIR=build/vault-redesign-validation
```

| Validation | Result |
| --- | --- |
| Swift/native tests | 1,016 selected tests completed across 21 runs, verified by completion receipts; 311 were headless app tests. |
| Python tests | All 112 passed in the final full run. |
| Structure and formatting | Swift formatting, shell syntax, package boundaries, architecture, localization/theme syntax and pinned vector-source checks passed. |
| Localization | All 22 catalogs passed completeness checks; extraction matched 1,308 source strings. |
| Native previews | 30 synthetic Vault previews reviewed across compact/wide, light/dark, empty/populated and failure states. Document fixtures assert a usable native reading viewport. |
| Packaged runtime | Signed debug build, text/TTS self-tests, benchmark fixture checks, all three helper parent-exit checks and catalog validation passed. |

The full command stopped at the TTS helper parent-exit check because its Python caller did not launch
the helper within the existing five-second startup deadline. The same isolated check initially timed
out again, then passed unchanged; text and search helper checks also passed, followed by catalog
validation. The host reported a load average above 180 during this interval. These results establish
successful lifecycle checks on retry, not a clean first-pass `make check` exit. No deadlines or test
expectations were relaxed. Earlier Python benchmark startup timeouts also passed on rerun unchanged.

Local evidence is in `build/vault-ui-review/audit-make-check.log`,
`build/vault-ui-review/audit-catalog.log` and `build/test-results/run-pquel363/verified.json`.
Earlier scale measurements remain in the [workspace qualification report](vault-workspace-2026-11-07.md);
the million-record benchmark was not rerun for this presentation and lifecycle audit.

Sixty GUI-only tests were excluded by the headless test policy. Visible window activation, focus
traversal, z-order and display-frame timing were not exercised in this pass. No claim of flawless
behavior across all hardware or all languages follows from these checks.
