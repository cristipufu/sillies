# Vault workspace: implementation and qualification

**November 7, 2026 · Apple M4 Pro, 48 GiB memory · macOS 26.7.2 (25G332)**

The Vault now has an adaptive sidebar/list/document workspace, authored notes, revision-safe editing,
collections/tags/saved searches, local semantic retrieval, recoverable Trash, streaming Markdown export,
local backup/restore and explicit URL/X/YouTube saving with asynchronous previews. Existing source captures and
companion conversations remain available from the same workspace. Scale and migration fixtures use
disposable data. An earlier local development Vault is reset only with the user's explicit approval;
no compatibility layer for intermediate workspace previews was added.

## What changed

| Area | Implementation | Evidence |
| --- | --- | --- |
| Navigation | One reusable native window and typed page owner; query/document/draft history; 100-header pages; independent search/detail readers; inline reading/playback | Headless transition/layout and lifecycle regressions; million-record concurrent search probe |
| Long documents | 16-block native reading pages, bounded edits, lazy source access | 7.2 MB synthetic document, zero full-body decodes for page/edit operations |
| Editing | Field-based metadata drafts; revision-based text drafts; original transcript retained; modal-safe save | Navigation/restart, conflict, save-as-new, final-keystroke quit tests |
| Search | Word, phrase and literal FTS5 per block with boundary overlap; independent keyword/meaning results; date slices; optional native index; canonical candidate validation; rank fusion | Retrieval comparison, synthetic ANN probe, correction/deletion/provider/restart tests |
| Links | Durable save first, public oEmbed/native metadata second; local thumbnail; retryable missing preview | URL/host validation and HTML-text tests; no embed scripts or authenticated scraping |
| Organization | Stars, Keep, source/date/tag filters, collections and saved queries; durable Trash/retention deletion selections reclaimed in slices | Persistence/workspace tests; count consistency across deletion and protection |
| Portability | Page-streamed Markdown plus files; source-linked quotations; SQLite backup and prepared next-launch restore preserving the prior archive | Backup reopen, pinned snapshot during concurrent saves, draft/Trash/file preservation, missing attachment and cancellation regressions |
| Isolation | Native index only in search helper; vendored official Faiss/LLVM; capped work and input validation | Package/import boundary fixtures; pinned-file checks; native checkpoint tests |

## Storage performance

`VaultScaleBenchmark` was built in release mode. A **synthetic** archive was created through the actual
`VaultLibrary`/`VaultDatabase` commit path, in resumable 20-second slices. It contains 1,000,000 records
with a short transcript, summary and action items; it is not a million full-length recorded meetings.
The final query run used 15 samples, with median and **nearest-rank p95** (the maximum for 15 samples).
The OS file cache was not controlled. First accesses are included, but this is not a qualified cold-cache
comparison or a stable tail-latency estimate.

| Operation at 1,000,000 records | Median | p95 | Full source bodies decoded |
| --- | ---: | ---: | ---: |
| Open a recent 100-item page | 1.46 ms | 2.66 ms | 0 |
| Broad keyword, newest first | 133.04 ms | 222.84 ms | 0 |
| Recently edited, 100-item page | 1.38 ms | 2.06 ms | 0 |
| Rare keyword, one result | 0.22 ms | 1.89 ms | 0 |
| Broad relevance query matching nearly all records | 5,402.47 ms | 42,075.50 ms | 0 |

The broad relevance query is a real limitation: FTS relevance still ranks/groups a large matching set.
It is cancellable and off the UI/writer/detail queues; it is **not** sub-second at this scale. Its first
sample took about 42 seconds; the later samples were about 5.4 seconds. The default date order uses
bounded chronological candidates and batched excerpts. Its p95 also exceeded the proposed 200 ms keyword
target in this run. Narrowing by meaningful words or filters reduces work; arbitrary search and bulk
maintenance are not constant-time.

A separate concurrent probe started that broad query, then read document pages, saved a star change,
cancelled the query and reused its reader:

| Concurrent operation | Measurement |
| --- | ---: |
| Document-page read median / p95 (15 samples) | 0.033 / 1.806 ms |
| Save while search runs | 13.963 ms |
| Cancellation acknowledgement | 0.153 ms |
| Subsequent recent-page read | 1.692 ms |

A separate **7,200,000-byte authored note** took 775.82 ms to create, 0.82 ms to read a middle page
(16 blocks), and 90.76 ms to replace that page. These operations decoded zero full source bodies.
The document remained in block storage; the benchmark did not open it as one giant native text view.

Keep-200 retention on a disposable copy acknowledged its durable selection and returned a snapshot in
1,394.16 ms; the following workspace page took 2.68 ms. Clear-all acknowledged its durable selection in
62.50 ms, and the following empty workspace page took 0.79 ms. Both decoded zero source bodies;
physical cleanup was still pending. A covering metadata index keeps pending-deletion counts from loading
source-body pages, and a sequence visibility check avoids scanning hidden records for an empty page.
These are single-run maintenance observations with uncontrolled background load, not latency guarantees
or controlled before/after comparisons.

Raw samples, fixture counts and reproducible arithmetic checks are in
[the data directory](data/vault-workspace-2026-11-07/). These are database/worker times, not display-frame
latency or an end-to-end audio benchmark. The keyword indexes and content backfill are complete in this
fixture; this does not measure initial migration of one million existing full-length recordings.

## Semantic retrieval

### Actual embedding-provider path

The production local embedding/helper/SQLite/native-index path was exercised using
`intfloat/multilingual-e5-small` revision `614241f622f53c4eeff9890bdc4f31cfecc418b3`, with the existing
76-query multilingual retrieval fixture saved as Vault documents. The fixture was frozen; expected
answers were not modified to fit the implementation.

| Ranking policy | Positive queries with an expected item in top 5 |
| --- | ---: |
| Keyword results first, then semantic extras | 47 / 57 |
| Reciprocal-rank fusion | 51 / 57 |

Four positive cases improved; none lost their expected hit. The scorer validates query completeness,
unique result identities and known document IDs. Reproduce it with
`python3 docs/reports/data/vault-workspace-2026-11-07/score-retrieval.py`.

This is a **retrieval regression comparison**, not an overall quality score. The source fixture was
designed for companion memories: some absent/foreign-owner expectations are not valid for a global
Vault. Those cases are excluded from the positive-hit metric; this result does not establish precision,
privacy isolation or no-answer behavior. This small corpus uses the exact native index, so it also does
not qualify approximate retrieval at one million real embeddings.

### Approximate-index prototype

An index-only probe used pinned Faiss, 384-dimensional synthetic vectors arranged in 256 clusters,
16,384 training samples, 100 held-out queries and an exact-search reference. The prototype used a local
OpenMP installation; the product builds pinned LLVM sources directly and does not require that install.

| Vectors | Recall@10 | Query median / p95 | Build | Peak RSS of probe |
| --- | ---: | ---: | ---: | ---: |
| 100,000 | 98.3% | 0.956 / 1.066 ms | 0.441 s | 172 MB |
| 1,000,000 | 98.3% | 7.368 / 8.511 ms | 4.025 s | 954 MB |

Clustered synthetic data is favorable to this index family. The probe's RSS includes generated vectors
and exact-reference work; it is not an app or helper memory budget. Native product tests separately
exercise on-disk checkpoint/reopen/removal and canonical deletion/provider invalidation. A diverse,
large real-embedding corpus remains necessary before asserting a large-corpus recall percentage.

## Audit findings fixed

The [UX audit](vault-ux-audit-2026-11-07.md) details the navigation and presentation pass, including
exclusive sidebar selection, page/history restoration, search from Storage/forms, interrupted reads,
empty-column alignment, conditional pagination and the rebuilt Storage page.

- Catalog validation was classified as ordinary app startup and could open personal persistence.
  It now exits through the automated runner before constructing application services. Input/writing
  fixtures also use automated launch policy; classification and permission regressions cover these modes.
- Clearing and explicitly re-saving the same capture could collide with sections awaiting deletion.
  An explicit insertion now retires that hidden identity before storing a fresh capture. This also
  rebuilds identical source text after partial reclamation; stale update commands still cannot revive
  deleted records. Native early-load and persistence restart regressions cover both paths.
- Search previews previously repeated the same broad FTS query for every visible row. One bounded
  excerpt query now serves the page. Headers and excerpts share a read snapshot, so concurrent edits
  cannot combine different revisions into one result page.
- Relevance/date cursors passed SQLite REAL values through text conversion, which rounded ties and
  could skip the next page. Native finite-double reads preserve the stored position; tied-score and
  fractional-timestamp pagination regressions verify complete, duplicate-free traversal.
- Global relevance now materializes each matched block score once and applies document filters after
  grouping. It still evaluates the entire matching corpus; the slow broad-query results remain above.
- Clear-all returned an empty count and then needlessly walked the old date index for headers. Empty
  snapshot pages now return directly, and a known smaller result set caps the requested page size.
  A sequence-based visibility check also skips workspace searches while all older records await
  cleanup. Fresh captures remain visible even when their dates precede those hidden records.
- File reference refreshes retain their visible data, expose loading separately and reject late results
  after record selection changes. The recording preview fixture now uses a real silent audio file.
- Native TextKit undo/redo could change visible text without notifying the editor delegate. Native
  undo completion notifications now synchronize the saved model; composition, autosave, undo and redo
  are exercised together with multilingual text in the headless native host.
- Successful text edits replaced content blocks while the editor retained their old source IDs. A
  commit now returns current references atomically, and quotations wait for saving. A multi-block paste
  regression verifies that immediately quoted text resolves to its current source.
- Switching companion archives could temporarily show the previous messages under the new name. Reader
  selection clears the old page immediately; real repository tests also verify companion filtering
  before search limits, using one conversation much busier than the other.
- Exact phrases and identifiers crossing storage-block boundaries now use a bounded search overlap.
  Replacement/deletion tests verify both FTS indexes and reject stale matches.
- New sections no longer issue empty FTS deletes or keep the old duplicate whole-document index.
  Protection is a metadata-only change; title renaming updates only its searchable section.
- Deletion selections are durable and immediately hidden from reads. Long records are reclaimed over
  multiple block slices, and new captures survive an earlier clear-all request. Recovery tests reopen
  unfinished jobs and verify owned files are removed only after canonical references are gone.
- Restore tests cover cancellation, invalid/oversized plans, interruption before/after installation,
  and restoring without an existing archive. All tests use disposable data.

- Draft edits could race navigation while a new document was loading. Editing now follows the load
  lifecycle, and recovered drafts restore their own source range.
- Late transcript pop-out requests could survive close/reopen. Request identity now owns completion.
- A legacy search fallback could return superseded text when another record still awaited migration.
  Fallback is now restricted to that pending set.
- Regenerating notes from a corrected transcript could replace its original source. Source preservation
  is covered through read, regeneration and save.
- Metadata edits now journal changed fields independently, preserving concurrent changes and final
  keystrokes during the modal termination loop.
- Backup initially inherited a journal mode that prevented portable reopen. The destination is now
  finalized using a fresh, exclusive connection before it is read/published. The exported folder has
  no WAL/SHM sidecars; cancellation or a missing attachment never publishes a partial backup.
- The compact link form could push Save/Cancel outside the window. Fields now scroll above a fixed
  action row. The retention menu uses explicit theme colors to keep its selection legible.
- Closing and reopening a long document preserves its reading page. Explicit record links leave
  the composer, storage and conversation panes before opening the requested item.
- Cancelling a link preview and immediately resuming cannot start an overlapping fetch. The original
  producer retains its queue slot until it returns, and stale completions cannot update the workspace.
- A failed first document load could appear as an empty library. It now shows the failure, retains its
  requested destination and offers Retry. Persistence failures also retain their explicit retry action.
- The replaced detail/header/transcript views were removed; the workspace has one production reading
  path. The lightweight Stash picker continues using its existing paged listing.
- The detail cache undercounted authored overlays. Its content cost now includes potentially replaced
  text conservatively and declines retention when it exceeds the budget.
- Native cache manifests, sparse training samples, interrupted writes, deletion and provider replacement
  have bounded validation/recovery. Retired cache files are unlinked without recursive metadata deletion.

## Validation and limits

`SILLIES_SKILL_UI_SNAPSHOTS=1 make check BUILD_DIR=build/vault-redesign-validation` passed with
**1,009 selected Swift/native tests across 21 runs** and **112 Python tests**. The check also completed
formatting, architecture/package boundaries, all 22 localization catalogs and source extraction,
inference-helper self-tests/parent-exit checks, native vendor integrity and bundled catalog validation.

Seventeen synthetic native previews were retained in `build/vault-ui-review`. Inspection included empty
and populated library states, forms, recording controls, conversations and Storage at compact/wide sizes
and in light/dark appearances. Navigation regressions cover every sidebar scope, Storage/form dismissal,
history and query restoration, search routing, cancelled opening and returning to the selected document.

Visible activation, z-order and display-frame GUI checks require explicit opt-in and were not run.
No multi-hour soak was used. Disk space, model inference throughput and storage maintenance remain finite;
this is evidence for bounded navigation/editing, not a guarantee of infinite capacity or zero latency.
The full million-record embedding/model pipeline, a million-record backup/complete physical purge,
and 8/16 GiB hardware were not benchmarked. Preview availability remains controlled by the source website. Backup covers the capture
Vault; companion conversations use their separate export controls.

## References

- [SQLite FTS5](https://www.sqlite.org/fts5.html), [online backup](https://www.sqlite.org/backup.html)
  and [WAL file lifecycle](https://www.sqlite.org/walformat.html#file_lifecycles).
- [Faiss index documentation](https://github.com/facebookresearch/faiss/wiki/Faiss-indexes) and
  [threading](https://github.com/facebookresearch/faiss/wiki/Threads-and-asynchronous-calls).
- [Reciprocal-rank fusion](https://cormack.uwaterloo.ca/cormacksigir09-rrf.pdf).
- [X's public publishing flow](https://help.x.com/en/using-x/how-to-embed-a-post).
- [Vendored source and regeneration contract](../../Vendor/VectorSearch/README.md).
