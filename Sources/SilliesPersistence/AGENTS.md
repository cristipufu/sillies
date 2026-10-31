# Persistence boundary

This target owns versioned SQLite records and safe filesystem operations and depends only on Core. APIs are synchronous and throwing; `SilliesVault.VaultLibrary` confines them to its actor off the main thread. SQLite is the initial Vault format for this unreleased app. Do not add a JSON archive migration. Future schema changes require explicit versioning. Corrupt, unsupported, or unreadable storage is an error, never an empty successful load.

`VaultDatabase` commits body, bounded header, and FTS5 document changes in one transaction. Page reads must not decode bodies. Updates to missing records must not recreate them. Search and retention operate on indexed metadata without loading transcripts. Bind all external SQL values and check native counts/conversions.

Use atomic replacement for attachment writes and file-only unlink for deletion. Validate filenames before I/O; attachments cannot refer to the database or its sidecars. Never recursively delete a path obtained from saved metadata. The database cleanup journal records filenames before writing new bytes and removes retired files only after committed metadata no longer references them. On reopening, preserve referenced files and finish only journaled cleanup.

`VaultWriteCoordinator` in the app owns per-ID coalescing and retains failed image payloads for Retry. Test missing/corrupt/unreadable storage, transaction rollback, attachment recovery, and deletion during background work. Run `make check`.

Fixed JSON examples in `Tests/SilliesPersistenceTests/Fixtures` exercise individual record codecs. They do not imply support for importing an old archive. Do not regenerate them with the current encoder; preserve unknown failure diagnostics and reject malformed fields.
