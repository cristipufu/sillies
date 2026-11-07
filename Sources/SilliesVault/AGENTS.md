# Vault application boundary

This target owns serialized Vault access, paging, bounded body retention, and background job admission. It depends only on Core, Persistence, and Reasoning. It must never import SilliesApp, AppKit, SwiftUI, audio capture, or a model SDK. The app owns presentation and supplies reasoning capabilities.

Listings contain `SessionRecordHeader`, never incomplete `SessionRecord` values. Load bodies explicitly by ID. Queue background work by ID; retain a body only while processing it. Every cache has a byte budget and every producer has stop/cancel semantics. Keep SQLite and filesystem operations off the main actor. Do not introduce shared instances or a service locator.

Conversation ranking uses its own serialized read-only connection, not the actor that owns saves, page reads and checkpoints. Check cancellation inside executing SQLite reads, not only before submitting a query. Scope progress handlers to reads so cancellation cannot interrupt transaction rollback. Clearing history invalidates pending search results. Verify writes and reads can complete while a broad search is still executing, and that a cancelled search leaves its reader reusable.

The package dependency policy and source import checks apply to every new file. Add short workload tests proving that page reads do not decode bodies, writes touch only changed records, stale updates cannot recreate deleted records, and cancellation does not publish old details.

Use `VaultRecordEdit` field commands for existing records. The native `VaultRecordEditor` serializes reads and edits, validates each read against current per-record revisions, and drains through modal-safe delivery before persistence flush. Never restore a whole UI snapshot. Notes and OCR have independent generation tokens; a replaced producer cannot complete newer work. Header paging uses `(createdAt, id)` cursors so inserting/deleting earlier rows cannot skip unseen records. `VaultChangeJournal` retains a bounded invalidation history; overflow requests a conservative first-page reload.

`VaultListing` owns the pure loaded-range merge, deduplication, cursor, and total-count rules. Keep debounce, request cancellation, selection, and error presentation in `SessionVaultModel`. Applying a new query result is one synchronous state change after the request's ownership check.

The workspace uses independent read-only owners for ranking, visible document blocks, exports and
assistant retrieval. Do not put a broad FTS query on the capture writer or selected-document reader.
`VaultWorkspaceModel` retains one 100-header page; `VaultTextEditorModel` retains a bounded block
range. Authored notes, corrected transcript/OCR and metadata drafts use revision/field commands,
never source-body replacement. Flush draft journals through `MainRunLoopDelivery` before quit.
A recovered conflict can be copied or saved as a new note; never force a stale revision.

Native vector search is an optional injected capability. `SilliesVectorIndex` is loaded only by
`SilliesSearchInference`; no C++ index or tensor SDK enters Vault or the app. Canonical vectors live
in SQLite. Every native candidate is revalidated against current record/block/provider state.
Interrupted caches rebuild; deletion and provider replacement retire derived files. Queries never
train an index. See `docs/contributing/vault.md` and the native index lifecycle tests.
