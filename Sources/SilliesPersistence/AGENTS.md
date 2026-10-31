# Persistence boundary

This target owns the session file format and safe filesystem operations and depends only on Core. APIs are synchronous and throwing; the app schedules them on its I/O worker. Preserve identifiers, saved keys, and ISO8601 dates. A missing index is empty; corruption, permission failure, and unreadable storage are errors, never an empty successful load.

Use atomic replacement for writes and file-only unlink for attachment deletion. Validate names on decoding and before I/O; attachments cannot refer to the metadata index. Never recursively delete a path obtained from saved metadata.

`VaultCommitRepository` owns attachment/index commit ordering and the cleanup journal. Write new attachments before committing their metadata; remove retired attachments only after the committed index no longer references them. Keep the journal reserved from attachment APIs and test recovery after an interrupted commit. `VaultWriteCoordinator` in the app owns coalescing and retains failed image payloads for Retry.

Example: a new attachment format extends record decoding and `VaultFileStorage`, while `SessionVaultStore` remains responsible for retry/merge/UI state. Add missing/corrupt/unreadable/recovery tests in `Tests/SilliesPersistenceTests` and app merge/lifecycle tests where appropriate. Run `make check`.

Fixed historical JSON examples live in `Tests/SilliesPersistenceTests/Fixtures`. Do not regenerate them with the current encoder. Preserve every original field on load/save, including the legacy `failureMessage` key alongside the additive typed `failure` value. Incompatible format changes require explicit versioning and migration.
