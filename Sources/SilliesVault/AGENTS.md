# Vault application boundary

This target owns serialized Vault access, paging, bounded body retention, and background job admission. It depends only on Core, Persistence, and Reasoning. It must never import SilliesApp, AppKit, SwiftUI, audio capture, or a model SDK. The app owns presentation and supplies reasoning capabilities.

Listings contain `SessionRecordHeader`, never incomplete `SessionRecord` values. Load bodies explicitly by ID. Queue background work by ID; retain a body only while processing it. Every cache has a byte budget and every producer has stop/cancel semantics. Keep SQLite and filesystem operations off the main actor. Do not introduce shared instances or a service locator.

The package dependency policy and source import checks apply to every new file. Add short workload tests proving that page reads do not decode bodies, writes touch only changed records, stale updates cannot recreate deleted records, and cancellation does not publish old details.

Use `VaultRecordEdit` field commands for existing records. The native `VaultRecordEditor` serializes reads and edits, validates each read against current per-record revisions, and drains through modal-safe delivery before persistence flush. Never restore a whole UI snapshot. Notes and OCR have independent generation tokens; a replaced producer cannot complete newer work. Header paging uses `(createdAt, id)` cursors so inserting/deleting earlier rows cannot skip unseen records. `VaultChangeJournal` retains a bounded invalidation history; overflow requests a conservative first-page reload.

`VaultListing` owns the pure loaded-range merge, deduplication, cursor, and total-count rules. Keep debounce, request cancellation, selection, and error presentation in `SessionVaultModel`. Applying a new query result is one synchronous state change after the request's ownership check.
