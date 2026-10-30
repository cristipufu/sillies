# Persistence boundary

This target owns the session file format and safe filesystem operations and depends only on Core. APIs are synchronous and throwing; the app schedules them on its I/O worker. Preserve identifiers, saved keys, and ISO8601 dates. A missing index is empty; corruption, permission failure, and unreadable storage are errors, never an empty successful load.

Use atomic replacement for writes and file-only unlink for attachment deletion. Validate names on decoding and before I/O; attachments cannot refer to the metadata index. Never recursively delete a path obtained from saved metadata.

Example: a new attachment format extends record decoding and `VaultFileStorage`, while `SessionVaultStore` remains responsible for retry/merge/UI state. Add missing/corrupt/unreadable/recovery tests in `Tests/SilliesPersistenceTests` and app merge/lifecycle tests where appropriate. Run `make check`.
