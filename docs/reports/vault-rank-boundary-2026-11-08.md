# Vault relevance ranking and result previews — 8 November 2026

This follow-up addresses the broad Best match query left open by the
[app acceptance pass](app-acceptance-2026-11-08.md). It changes first-page query planning, not the
ranking function, search corpus, user interface or semantic model. It also fixes an expensive
lookup while generating the visible page's previews.

## Approach

The old query scores all matching passages, groups them into records, filters the records, and
sorts the complete result set before loading 100 visible headers and one lookahead result.
On broad searches, the intermediate grouping can contain millions of rows.

The new query first examines at most 4,096 matching passages. If those passages establish 101
distinct eligible records, their worst `(BM25 score, record ID)` supplies an exact upper bound
for the first page. The final scan still scores every matching passage; only passages that can
compete with that bound need grouping. No fixed candidate limit truncates the search.

Why this is safe: every sampled record's actual best passage is at least as good as its sampled
passage. There are already 101 distinct eligible records at or above the boundary. A worse passage
cannot place its record ahead of those 101. Every competitive record retains its actual best
passage, so its score and the record-ID tie break remain unchanged.

Both reads share the existing SQLite read snapshot and cancellation scope. The seed uses the same
workspace filter and cleanup visibility as the final query. If fewer than 101 eligible records can
be established, the original complete aggregation runs. Continuation pages also retain complete
aggregation: filtering individual passages by a cursor could otherwise repeat a record through
one of its weaker passages.

The end-to-end comparison also exposed a separate excerpt cost. SQLite scanned the 100 wanted
block IDs for every matching passage between their smallest and largest IDs. This was especially
expensive when UUID ordering selected records scattered throughout the archive. The excerpt query
now joins a connection-local TEMP table with an integer primary key. It retains one FTS cursor,
performs indexed membership checks and still reads text only for the visible page. The table holds
at most 100 IDs, replaces its selection for each page and disappears when its reader closes. It
never changes the archive schema. A rolled-back first read recreates the table on the next request.

SQLite documents the distinction between its hidden `rank` column and ordering by the BM25
function, as well as the stored token counts required by BM25. The existing stored counts and
ranking function remain in use. See [FTS5 ranking](https://www.sqlite.org/fts5.html#sorting_by_auxiliary_function_results)
and [column sizes](https://www.sqlite.org/fts5.html#the_columnsize_option).

## Validation scope

An independent oracle materializes and ranks all matching passages without the optimization.
Regression scenarios compare identities, best passage locations and cursor scores for:

- Stronger matches and record-ID ties outside the preparation sample.
- Word, phrase and literal substring searches.
- Active records, Trash, starred items, meetings, tags, source filters, dates and no matches.
- Continuation pages, including records with multiple matching passages.
- A single long document occupying the preparation sample, requiring complete aggregation.
- Records awaiting physical deletion, which must not establish a relevance boundary.
- Excerpt selection on a read-only archive, rollback recovery and replacement by a smaller page.

The full persistence suite passed 87 checked tests. Twenty-four additional queries on the public
retrieval corpus preserved complete `(record ID, score, block ID)` result rows for words, phrases and
substrings in the SQL experiment's query shapes.

## Release-build comparison

Both conditions use the existing `VaultScaleBenchmark query` workload through `VaultLibrary`.
Each fixture runs baseline / changed / changed / baseline, with 15 samples of each operation per run.
The table pools all 30 samples per condition, including first samples and outliers. p95 is nearest-rank.

| Broad Best match fixture | Median before → after | p95 before → after | Median reduction |
| --- | ---: | ---: | ---: |
| 100,000 records, random UUIDs | 943.94 → 416.26 ms | 1,077.62 → 440.00 ms | 55.9% |
| 1,000,000 records, ordered UUIDs | 4,887.93 → 3,910.89 ms | 7,178.54 → 5,991.99 ms | 20.0% |

Recent-page medians remained about 1.6 ms. At one million records, broad Newest first measured
161.62 → 158.90 ms. Rare-query medians increased from 0.24 to 0.37 ms because the new preparation has
a small fixed cost. The benchmark reported zero body loads on its writer-owned counter. That counter
does not cover the separate search reader; direct read-only persistence regressions independently
assert that the ranking/preview path decodes no source bodies. It is not a memory-usage measurement.

The isolated excerpt probe selects 100 blocks spread throughout each fixture, including TEMP setup
in the changed condition. It returned identical ID/excerpt fingerprints. Warm observations were
approximately 363 → 14 ms at 100,000 records and 3,717–3,886 → 138–153 ms at one million. These are
excerpt-only measurements, not end-to-end search times. The million-record public-API query selects
nearby blocks because that fixture's UUIDs follow insertion order.

An earlier boundary-only release comparison was inconclusive at one million records: pooled medians
were 4.68 versus 4.76 seconds, with substantial variation in both conditions and in unchanged operations.
Those samples remain in the evidence bundle. The later combined comparison, rather than the earlier
SQL prototype or a selected fast sample, supports the published improvement.

While a million-record search was running, a separate detail read measured 0.045 ms median / 2.49 ms
p95; a metadata save took 2.08 ms. Cancelling the search completed in 11.93 ms, and the next page read
took 2.41 ms. This single bounded concurrency probe supports reader/writer isolation and cancellation;
it is not a native display-frame measurement.

## Limits and final checks

Measurements used an Apple M4 Pro with 48 GiB RAM on a shared working Mac. This task ran no compilation
or test suite concurrently with its measurements, but unrelated system activity and filesystem cache
were not controlled. Initial samples are not cold-start benchmarks. The maximum final million-record
samples were 24.36 seconds before and 9.49 seconds after; neither is a guaranteed worst-case bound.

The million-record fixture contains short synthetic records, not a million full meetings. Broad
Best match still takes seconds, and continuation pages retain complete aggregation. The optimized
excerpt lookup applies to continuation pages as well. Native GUI checks were not requested in this
pass. No semantic relevance scores or model rankings changed.

`make check` passed: 740 reusable tests across 20 checked runs and 328 native headless tests in one
checked run, plus formatting, 127 Python tests, architecture/localization validation, packaged helper
self-tests, parent-exit checks and catalog validation. The focused persistence run passed 87 tests.
The preceding acceptance pass's stress and race results remain recorded there; those suites were not
repeated for this SQL-only follow-up. The running app was not restarted during the measurements.

[Raw measurements, source identities and reproduction notes](data/vault-rank-boundary-2026-11-08/README.md).
