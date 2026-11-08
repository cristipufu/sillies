# The Vault

The Vault keeps recordings, screenshots, notes, links and companion conversations accessible from one
workspace. Browsing opens lightweight headers; selecting an item loads only the current reading page.

## Everyday use

| Action | Where to go |
| --- | --- |
| Write something | **New note** (`⌘N`). Edit the title, add comma-separated tags, and write in Markdown. Changes save automatically. |
| Save an article, X post or YouTube video | **Save link**. Paste the URL and optionally add a title and notes. The URL saves before its preview downloads. Open the source in your browser. |
| Find something | Search (`⌘F`), then narrow by category, collection, tag, date, app, companion or language. Choose Words & meaning, Exact phrase or Exact text, then a date or Best match order; **Related by meaning** adds local semantic matches. |
| Organize | Star important items, add them to collections, or save a filtered search. Multiple selection supports stars, collection membership, export and Trash. |
| Review a recording | Switch between notes, summary, transcript and original transcript. Playback stays inline, with clickable page cues, speed, bookmarks and optional Follow audio. Scrolling, editing or selecting text pauses following. |
| Correct source text | Edit Transcript or Screenshot text. Transcript corrections retain the original source separately. Generated summaries stay separate from personal notes. |
| Find an earlier conversation | Choose Conversations, or search All items. Read a bounded message page inline and continue in the companion's Chat. |
| Quote a passage | Select text and quote it into a new note or existing My notes. The saved quotation includes a portable source link. You can also export only the selection. |
| Paste a captured item back | Open the Vault from the destination app, then use **Paste into…** in a captured item's menu. The destination is revalidated before insertion; a changed or unavailable field leaves the saved item intact. |
| Find a moved Stash file | Use **Relink…** in File references. Removing the Vault item never deletes the external target. |
| Keep a copy | Export an item or the library as Markdown with attachments. **Storage & retention** also offers a local Vault backup. |
| Remove something | Move it to Trash, then restore it or explicitly delete it permanently. Retention limits permanently remove eligible old captures; notes, links, Stash, protected and starred items are exempt. |

A preview can be unavailable because a post is private, deleted, offline or blocked by its host. Retry
from the item's menu; the saved URL and notes remain usable. Videos open in the browser. Sillies does
not download videos, scrape authenticated pages, run embed scripts or promise video transcripts.

## Ownership and extension points

| Responsibility | Owner | Contract |
| --- | --- | --- |
| Query, document metadata, sections, edits and drafts | `SilliesCore` | Typed values, no UI or storage services |
| Canonical data and transactions | `SilliesPersistence.VaultDatabase` | Versioned SQLite; source, authored sections and derived indexes have distinct ownership |
| Application access and background preparation | `SilliesVault.VaultLibrary` | Actor-owned writes, explicit full-body reads, cancellable independent readers |
| Workspace navigation | `VaultWorkspaceModel`, its `VaultNavigation` | One typed page; one derived sidebar selection; bounded query/document/composition history; independent document lifetime |
| Interactive search | `VaultWorkspaceSearch` | One bounded result page, independently cancelled keyword/semantic tasks, 100 remembered page cursors |
| Reading and editing | `VaultDocumentModel`, `VaultTextEditorModel`, `VaultMetadataEditor` | Bounded native text viewport, field/revision edits, durable recovery drafts |
| Native window and commands | `SessionVaultWindowController`, `SessionVaultModel` | One reusable window; modal-safe flush; late actions cannot reopen a closed lifetime |
| Link enrichment | `VaultLinkPreviewFetching`, app preview coordinator | Durable pending state, one background fetch, bounded bytes/time, explicit stop |
| Native semantic acceleration | `SilliesVectorIndex` inside `SilliesSearchInference` | Optional injected capability; no C++ or model SDK in the app or Vault target |
| Export, backup and restore | Independent export/backup/restore workers | Bounded copies; prepare restore separately and activate before opening the live database |
| Permanent cleanup | Durable selections in Persistence, application-owned yielding worker | Hide pending deletions immediately, reclaim blocks and files in slices, resume after restart |

To add a document section, define its domain identity, source projection, editing ownership and export
heading. Add UI labels/translations, indexing rules and failure/cancellation tests. Do not add a new
whole-record editor or put filesystem work in a view. A new preview provider implements the existing
fetch contract; keep URL classification, network access and rendering separate.

oEmbed refreshes replace provider-owned titles and descriptions while preserving a custom document
title. HTML excerpts decode terminated character references once using a generated WHATWG lookup.
The table is pure compiled data in Core, with no runtime file or network access. To update it, download
`https://html.spec.whatwg.org/entities.json` and run
`python3 scripts/generate-html-character-references.py /path/to/entities.json`, then format the generated
Swift file. Review its recorded checksum, the retained WHATWG license and the excerpt/refresh regressions.

Document list rows show a title and date without a repeated description or empty text slot. Search
passages remain available on demand. Keep ordinary rows compact at narrow widths; the layout fixture
also covers long titles, stars, absent descriptions and light/dark appearance.

Screenshot records open on the image; explicit search matches open their matching text section.
`VaultDocumentPane` owns the selected surface independently of the last loaded text section. Image,
text and attachment navigation must flush pending edits and disable actions for concealed text.
Previews use the bounded media cache and worker decoding, with a retryable missing-image state.

Screenshot OCR uses Vision document recognition on a worker. The native adapter passes recognized fragments,
bounds, writing direction and detected tables into Core's `ScreenshotTextLayout`. Vision observations
can split a physical line into separate words or labels. Reassemble aligned fragments before adding
indentation; whitespace cuts keep independent columns separate. Never treat each observation as a
complete reading line or reconstruct global X offsets as padding for every word. The native text editor preserves indentation with a monospaced
font. Layout recognition is best effort, and the original image remains available. OCR completion
refreshes the visible text after the persistence barrier; retries must preserve authored corrections.
Keep image-first navigation, missing-file recovery, OCR cancellation and late-completion regressions
in `VaultScreenshotTests`, with geometry boundaries in `ScreenshotTextLayoutTests`.
`VaultOCRReadingTests` verifies native recognition through the actual Vault editor. For a private
capture review, run it with `SILLIES_SKILL_UI_SNAPSHOTS=1` and `SILLIES_OCR_REVIEW_IMAGE=/path/to/image.png`;
the optional preview stays in the temporary snapshot directory. Do not add private captures to fixtures.
Review physical reading lines and their rendered appearance, not indentation or paragraph counts alone.

Library scopes, Storage, composition and source quotations must go through the workspace navigation
methods. Do not add independent editor/section flags to the view or native controller. A same-section
selection still dismisses compact navigation, without adding a duplicate history entry. Deferred creation
must validate its originating page before selecting its result. See the
[UX audit](../reports/vault-ux-audit-2026-11-07.md) and `VaultWorkspaceNavigationTests`.

Deferred document actions carry the record identity from the click and revalidate ownership after
awaiting I/O. Bulk commands require the current applied query and visible selection. Bound long
diagnostics with the shared notice viewport, keep recoverable failures readable until dismissed, and
reject invalid native text ranges before calling AppKit. `VaultUsabilityAuditTests` covers these
boundaries together with category layouts, active filters, incomplete forms and conversation retries.

## Storage and editing

Schema 3 upgrades the existing SQLite archive transactionally. It creates a durable backfill queue;
existing source bodies are projected one record at a time, outside the main thread. Opening a selected
old record prepares that record immediately. Canonical record IDs remain stable. This is a SQLite
schema upgrade, not an importer for a pre-release JSON archive.

Schema 4 adds covering metadata and attachment-reference indexes. The relevance reader uses
`available_search_records` so filtering a large matching set does not fetch source-body pages.
Both visibility views share `VaultCleanupSelection.recordVisibility`. Read-only schema-3 backups
remain copyable; launch upgrades the installed copy. Changes to indexes require a transactional
schema version and migration coverage, including the preceding backup format.

- Workspace pages contain at most **100 headers**. Source bodies are never decoded for list rendering.
- Reading pages contain at most **16 blocks**, each at most **2,048 Unicode scalars**. A growing edit is
  bounded to **128 blocks / 131,072 scalars**. Normal extended graphemes remain together at boundaries.
- Source summaries, transcript, OCR, personal notes, original transcript and labels have separate
  sections. Source processing cannot overwrite a section the user corrected.
- A draft is written before the canonical edit. Text commits compare revisions; metadata commits
  change only edited fields. A conflict preserves the draft and offers **Save as new note**.
- A committed draft returns its current block identities in the same transaction. Quoting waits for
  the save, so an immediately edited passage cannot retain a deleted source ID. Native undo/redo
  completion notifications synchronize the text model before autosave; composition stays native.
- Draft flushes join the app's modal-safe termination path. Navigation does not discard a failed,
  unjournaled edit. Full-record consumers use a conservative **8 MiB / 16-entry** content cache;
  corrected text and authored notes count toward its budget.
- Tag/collection membership per item and organization lists are bounded (32 tags, 32 collections per
  item, 500 collections and 500 saved searches). Invalid saved bounds fail explicitly.
- Protection changes update indexed metadata without decoding or rewriting a source body. Explicit
  body reads overlay the authoritative protection column.
- Permanent deletion and retention save their selection before reclaiming data. Each cleanup slice
  removes at most 100 source rows and 512 content blocks; file cleanup handles at most 128 journaled
  paths. New captures survive an earlier clear-all request. Closing the Vault does not lose the job;
  pause/termination stops its producer, and the next launch resumes it. Failures remain visible with Retry.

Keyword ranking, selected-document reads and assistant retrieval have separate read-only connections.
SQLite progress callbacks interrupt cancelled reads. They cannot interrupt write rollback. A page’s
headers and batched excerpts share one read snapshot. Cursor positions retain SQLite’s native finite
double value rather than a rounded text conversion. Revision checks prevent stale results from
publishing after edits or deletion.

## Search and its limits

FTS5 indexes editable content blocks, including authored notes, tags and saved-link descriptions. The
original transcript is excluded so an old correction does not reappear as current evidence. A fallback
search during migration is restricted to records still awaiting backfill. New captures do not keep a
second whole-document FTS copy. Search text overlaps the next block by at most 512 Unicode scalars so
phrases and identifiers spanning a storage boundary remain searchable; old indexed input is retained
for correct transactional invalidation. Original and semantic source blocks are not duplicated.

Word search uses Unicode tokenization; Exact text uses an additional FTS5 trigram index, requires at
least three characters, and preserves punctuation for identifiers/URLs and non-Latin substrings. Exact
modes currently apply to saved notes and captures; Words & meaning also includes conversations.
Date ordering uses sparse posting lists or 256-record chronological slices with stable continuation;
Best match scores every matching block. Its first page can prune grouping using a proven boundary
from 101 distinct eligible records found in a bounded preparation sample. The sample never caps the
final scan. Incomplete samples and continuation pages retain full grouping; cursor filtering follows
each record's best passage so weaker passages cannot repeat an earlier result. SQLite's unlimited
subquery boundary prevents flattening from placing its FTS rank function inside an aggregate.

Visible excerpts use one FTS cursor and a connection-local TEMP table containing at most 100 block
IDs with integer primary-key lookup. An unindexed VALUES cross join scans all wanted IDs for every
matching passage and becomes expensive when selected records are scattered through the archive.
Replace the selection on each read, recreate it after rollback, and never write it into the archive.
The UI preserves the chosen date order when typing. Empty search slices yield and remain cancellable
rather than becoming a false “no matches” result. See the
[ranking and preview qualification](../reports/vault-rank-boundary-2026-11-08.md).

Embeddings come from the selected local provider: Apple by default, or an optional downloaded search
model. Canonical vectors, provider identities and change cursors live in SQLite. Keyword and semantic
rankings use reciprocal-rank fusion for assistant retrieval; the workspace labels supplemental semantic
matches separately. Search misses never erase the keyword results.

The optional native index uses exact search while its vectors fit the small-index budget. Larger
indexes use **Faiss IVF-SQ8 with memory-mapped inverted lists**, bounded training input and two OpenMP
workers. IVF queries scan every partition while encoded vector codes plus row IDs fit 32 MiB;
larger indexes probe at most 96 partitions. This budget does not make SQ8 distances exact. The
canonical reranking candidate limit remains 256. Maintenance runs in slices; queries never rebuild/train an index. Dirty/opening markers,
provider epochs, change-log coverage and canonical row validation make stale or interrupted caches
rebuildable. Deleted/provider-retired index files are removed during maintenance. Filters can use
canonical exact ranking; semantic deadlines keep slow inference/search from delaying visible keyword
results indefinitely.

Approximate search is not a promise of perfect recall. Broad relevance queries still scale with the
number of matching blocks. The [qualification report](../reports/vault-qualification-2026-11-07.md)
distinguishes database latency, index fidelity, actual model retrieval and passage coverage.
The [search follow-up](../reports/vault-search-refinement-2026-11-08.md) adds provider-aware capacity
handling, expanded multilingual evidence checks, scoped semantic retrieval and rejected exact-ranking
experiments. The [app acceptance follow-up](../reports/app-acceptance-2026-11-08.md) records adaptive
small-index coverage, canonical saved-link evidence and lifecycle regressions. Broad Best match
remains the slow path at million-record scale.

## Export and backup

Markdown export streams section pages, checks revisions, copies referenced attachments, and publishes
one complete item folder at a time. Earlier completed items remain valid if a later item fails or the
user cancels. Individual exports retain original and corrected transcripts.

A Vault backup uses SQLite's online backup API with a pinned source snapshot and bounded page copies.
Referenced files are enumerated in batches of 128 owning records by merging ordered partial indexes
for source files and preview-only files. Fileless records do not require a per-record call or sort;
tests assert both complete traversal and the actual SQLite query plan.
It finalizes its private destination in rollback-journal mode before publishing, without WAL/SHM
sidecars. It includes `vault.sqlite`, drafts, Trash, collections and referenced attachments. An attachment removed
concurrently causes an explicit failed backup, not a successful folder with missing files. It excludes
`conversations.sqlite`, downloaded models and disposable native index files; conversations have their
own export controls in Chat. Treat a backup as private data.

**Restore Vault backup…** in Storage prepares and validates a separate copy. It activates at the next
app launch, before SQLite connections open. The previous Vault is moved to a separate recovery folder;
it is never overwritten in place. You can cancel a prepared restore. Interrupted installations resume,
and successful restoration resets automatic retention to Keep everything so recovered records are not
immediately trimmed. Restore does not replace the companion conversation archive. A malformed,
incomplete or incompatible backup reports an error and preserves existing files.

## Verification

Catalog validation runs before application service composition and does not open the user's Vault.
Automated fixtures use temporary storage and preferences; never validate a development schema against
personal data. Unreleased intermediate workspace layouts can be reset locally with explicit consent;
there is no importer for those previews. Preserve the separate conversation database during a capture reset.

`make check` runs headless by default. Focused suites cover source preservation, draft conflicts,
modal quit, navigation lifetimes, backup cancellation, migration, deleted evidence, native checkpoint
restart, provider resets and on-disk index updates. The package and import checker rejects native-index
access outside the search helper. `scripts/verify-vector-vendor.py` checks pinned upstream files.

For bounded qualification, build `VaultScaleBenchmark` in release mode. `seed` creates only synthetic
records in the supplied directory and stops after the specified time slice; repeat until its target
is reached. Never use your personal Vault directory.
The probe's `loadedBodies` field comes from the library writer's metrics, not an aggregate of its
independent readers. Use the read-only persistence regressions for the search-reader body-loading
invariant; neither counter measures resident memory or native display latency.

```sh
swift build -c release --product VaultScaleBenchmark
# Use the binary path reported by SwiftPM/Xcode for your build system.
VaultScaleBenchmark seed /tmp/sillies-vault-scale 1000000 20
VaultScaleBenchmark query /tmp/sillies-vault-scale 1000000 20
VaultScaleBenchmark concurrency /tmp/sillies-vault-scale 1000000 20
VaultScaleBenchmark long-document /tmp/sillies-vault-long 1 20
```

Query qualification runs 15 samples per query; its last argument bounds seeding only. Concurrency
briefly stars/restores one synthetic record while cancelling a broad search. Long-document mode creates
a synthetic 7.2 MB note and edits one middle page. These are short workload probes, not a multi-hour soak
or a claim that disk, CPU and memory are unlimited.

On separate disposable copies of the completed fixture, `retention` measures a keep-200 request and
`clear` measures a clear-all request, including the resulting snapshot and first workspace page.
These commands change the supplied synthetic archive. They measure acknowledgement while physical
cleanup remains pending; they do not measure the duration of a complete million-record purge.
Use resumable `drain` slices to verify completion, followed by physical row, search and attachment
checks. The [qualification procedure](../../Benchmarks/Vault/README.md) also covers complete backup,
next-launch restore, interrupted indexing, real embeddings and explicit native interaction checks.
