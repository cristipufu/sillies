# Stored Chat: one million messages, browsing and interrupted-write recovery

The [bounded-reply implementation](long-lived-chat-2026-11-03.md) was pushed as `cd18f9e` before
this follow-up. These checks extend its smaller SQLite and in-memory controls with real 100,000-
and 1,000,000-message databases, growing conversations, hidden native Chat views, and a killed
writer process. They also found and fixed a common-term search bottleneck.

## What the checks exercise

Each synthetic database is created through the production conversation persistence API, in
256-message batches. Messages alternate user/companion roles, contain distinct searchable markers,
include multilingual text, and periodically contain longer passages. All data is isolated from the
running app. Seeding is test setup, not the work done when a user opens an existing conversation.

For each size, the checked native runner verifies:

- **100 new turns:** save a new user message, prepare a reply through `LocalConversationService`,
  and save the assistant message. Exactly 200 messages are added. Each reply reads one checkpoint
  and one bounded recent page. Across the run, there are at most 1,000 token measurements and no
  foreground summaries.
- **Older pages:** 100 cursor pages, without overlap or crossing the previous boundary. Recent
  UI and inference pages never load the complete archive.
- **Search:** exact markers near the beginning, middle and end; two terms matching almost the
  entire seeded archive; and a term with no results.
- **Headless Chat:** restore the real session and SwiftUI/native text view; browse an older page;
  open a search result; select text; stream and complete a new reply while retaining the same old
  text view and selection; return to recent messages; save a draft and reading position; reopen
  persistence and verify the reply and checkpoint.
- **Process recovery:** a Swift child first commits a user message, unfinished assistant reply,
  spoken prefix, draft and reading position through production persistence. Test-only SQL then
  changes an old body and deletes its search row inside an uncommitted transaction. SQLite's
  cache-flush API writes dirty pages to the WAL without committing. The supervisor waits for a
  ready marker and a nonempty WAL, sends SIGKILL, and verifies the signal exit. A fresh native
  process verifies committed state, rollback of both pending changes, search consistency, and
  a successful subsequent write.

The recovery probe is deliberately separate from the app. It does not kill or restart the user's
Sillies instance, and it does not simulate power loss or damaged storage hardware.

## Measured search improvement

The original native million-message check failed its two-second search budget: `project` took
4.699 seconds and `résumé` took 5.036 seconds. Its reply preparation and paging still passed.

The query joined every FTS candidate to a message through its UUID index. The FTS row identifier
already equals the message's indexed numeric sequence. Joining on that sequence removes the
redundant UUID lookup. The first improvement kept the rest of the query unchanged.

A read-only SQL diagnostic compared the original query, the direct sequence join and a ranking
step filtering through FTS content. All returned identical IDs and ordering for the broad queries.
The simpler sequence join was faster in that diagnostic, which uses Python's SQLite 3.50.4; its
absolute timings are not substituted for the app's native measurements.

A separate native follow-up on the existing million-message fixture reduced those searches to
1.590 and 1.540 seconds. A complete fresh-database run then passed at 1.60–1.61 seconds. However,
another fresh run later took **2.783 and 3.406 seconds**, failing the unchanged budget. Reply work,
paging and main-actor scheduling also slowed in that run. System load varied; that observation
does not isolate the cause, and the failure is retained rather than discarded as noise.

A second diagnostic used the system SQLite 3.51.0 executable. It compared three queries against
the same database and verified all returned fields and ordering, not only IDs. The direct join
took 2.517 seconds; ranking through FTS content took 2.305 seconds; ranking numeric identities
through message metadata **before fetching bodies and owner names** took 1.573 seconds.

The final implementation uses that last query shape: a bounded, materialized set of scored message
IDs, followed by body/name retrieval for those results. It preserves full-corpus relevance scoring,
newest-first ties, companion filters, exclusions before limiting, and result limits. It does not
truncate the candidate corpus, change the schema, or introduce model-specific behavior. A regular
regression verifies those semantics and correct results after editing and deleting messages.

## Fresh-database results

The complete sequence passed at both sizes with the final query. Timings below are from the last
fresh-database run; the preceding native diagnostic passed at 1.34–1.36 seconds for broad searches.
The slower complete run is reported here rather than selecting the lowest observed timings:

| Measurement | 100,000 messages | 1,000,000 messages |
| --- | ---: | ---: |
| Restore latest page and checkpoint | 3.80 ms | 3.72 ms |
| New-turn application work, median | 2.11 ms | 2.18 ms |
| New-turn application work, p95 | 5.55 ms | 9.46 ms |
| Older-page load, maximum | 2.87 ms | 0.88 ms |
| Rare-term search, maximum | 0.30 ms | 0.58 ms |
| Broad-term search | 218–265 ms | 1.75–1.99 s |
| Main-actor handoff, maximum | 5.60 ms | 7.11 ms |
| Resident-memory increase | 12.03 MiB | 26.11 MiB |
| Foreground summaries across 100 turns | 0 | 0 |
| Native Chat browsing/selection checks | Passed | Passed |
| Killed-writer recovery in a fresh process | Passed | Passed |

New-turn application work includes saving the user message, preparing/completing the fake reply,
and saving the assistant message. It is not time to an actual model answer. Both recovery probes
had 556,232 bytes in the uncommitted WAL before SIGKILL. The two complete sequences took about
116 seconds together, including seeding, native test discovery, browsing and process recovery.
The slowest broad query is close to the two-second test budget; this is a measured improvement,
not a guarantee that every run or Mac will meet that limit under arbitrary load.

## Measurement scope

Apple M4 Pro, 48 GiB, macOS 26.7.2. Debug native test binaries; fresh test processes, but filesystem
caches can be warm after seeding. Inference is a deterministic fake so the timing measures
application preparation and durable writes, not model generation or TTS. Native model cancellation
and checkpoint generation have separate controls in the earlier report.

RSS is an end-minus-start observation over the storage workload, not peak memory or a leak proof.
The main-actor probe measures scheduling delay, not compositor frame time. The hidden Chat test
drives navigation through its model and a native scroll view; macOS exposes no button accessibility
tree for that hidden window, so this is not an on-screen click test. Visible activation, attachment,
stacking and display timing still require the explicitly requested GUI suite.

Broad search still scales with matching documents and is not instantaneous at a million messages.
These checks do not promise infinite disk space, constant-time search at arbitrary sizes, perfect
model memory, or identical latency on other Macs. They establish bounded foreground preparation,
bounded presentation data, and recovery behavior on these workloads without a multi-hour soak.

## Reproduce

Build the test binaries and run the search regression first:

```sh
bash scripts/test.sh --framework swift-testing --filter 'SilliesVaultTests.conversationSearchPreserves.*'
python3 -B scripts/check-conversation-scale.py \
  --bin-path .build/out/Products/Debug \
  --output build/conversation-scale-my-run
```

The script defaults to 100K and 1M messages, creates disposable temporary databases, and retains
them on failure. Use `--keep-databases` to retain successful fixtures too. Each seed has a
180-second deadline; each checked native test run has a 120-second deadline. Completion receipts
and explicit workload markers are required. A timeout, skipped workload, missing receipt or failed
assertion cannot become a successful run. Keep builds and other inference out of timing runs.

The smaller 2,000-message headless Chat check and search semantics regression run in normal
`make check`; the large databases and process interruption are opt-in.

`make check` passed: 680 selected native tests across 18 verified runs, 92 Python checks,
architecture/dependency checks, localization coverage and extraction, benchmark fixture validation,
packaged inference helper checks, helper parent-exit checks and catalog validation. The large-history
tests run separately with their required environment; their receipts are kept with the scale results.

The [evidence directory](data/stored-conversation-scale-2026-11-03/) retains the failed native search
baseline, query plans and diagnostic timings, successful follow-ups, checked test receipts, artifact
and source hashes, and the full-check log. These are engineering controls, not independent human
review or a new model-quality leaderboard.
