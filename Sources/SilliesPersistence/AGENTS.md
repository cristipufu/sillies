# Persistence boundary

This target owns versioned SQLite records and safe filesystem operations and depends only on Core. APIs are synchronous and throwing; `SilliesVault.VaultLibrary` confines them to its actor off the main thread. SQLite is the initial Vault format for this unreleased app. Do not add a JSON archive migration. Future schema changes require explicit versioning. Corrupt, unsupported, or unreadable storage is an error, never an empty successful load.

`VaultDatabase` commits body, bounded header, and FTS5 document changes in one transaction. Page reads must not decode bodies. Updates to missing records must not recreate them. Search and retention operate on indexed metadata without loading transcripts. Bind all external SQL values and check native counts/conversions.

Conversation search ranks bounded message identities before extracting query-relevant FTS excerpts. Never substitute the opening of a matching message for its relevant evidence. Keep original entries separate from excerpts, preserve speaker and chronology, and test details beyond long prefixes. Excerpt extraction must not move body decoding into the unbounded ranking pass.

Use atomic replacement for attachment writes and file-only unlink for deletion. Validate filenames before I/O; attachments cannot refer to the database or its sidecars. Never recursively delete a path obtained from saved metadata. The database cleanup journal records filenames before writing new bytes and removes retired files only after committed metadata no longer references them. On reopening, preserve referenced files and finish only journaled cleanup.

`VaultWriteCoordinator` in the app owns per-ID coalescing and retains failed image payloads for Retry. Test missing/corrupt/unreadable storage, transaction rollback, attachment recovery, and deletion during background work. Run `make check`.

Fixed JSON examples in `Tests/SilliesPersistenceTests/Fixtures` exercise individual record codecs. They do not imply support for importing an old archive. Do not regenerate them with the current encoder; preserve unknown failure diagnostics and reject malformed fields.

Saved-memory creation must not overwrite an existing canonical topic. Replacements resolve the
current identity and revision inside the write transaction; preserve original provenance on refusals.
Memory ranking belongs on the independent read-only search connection and selects bounded identities
before decoding bodies. Stored fact count must not become a prompt or UI array size: use
`CompanionMemoryQuery` for bounded retrieval and cursor pages for browsing.

Schema 3 separates source records from workspace metadata and editable section blocks. Stable block
IDs own FTS and semantic invalidation; changing an ordinal must not regenerate unrelated embeddings.
Preserve the original transcript when a corrected record is read, summarized or renamed. Original
transcripts are available for review/export but excluded from normal search and embedding queues.

Text/metadata drafts are durable before committing an edit. A revision conflict keeps the draft;
deleting its record cannot recreate the record. Read saved bounds and identifiers defensively.
SQLite online backup pins a read snapshot, copies bounded pages, closes the destination journal,
and publishes only after its referenced attachments have copied. Export and backup must leave no
successful partial result after cancellation. Never recursively delete a metadata-supplied path.
