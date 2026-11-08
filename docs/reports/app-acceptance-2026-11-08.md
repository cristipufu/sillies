# App acceptance and startup recovery — 8 November 2026

This pass started from pushed commit `926b026`. It covered search, everyday workflows, saved-information
retrieval, model setup and lifecycle recovery. During validation, a live report of missing companions
revealed a separate Accessibility boundary bug, also fixed in this pass.

## Changes and evidence

| Area | Finding | Change | Validation |
| --- | --- | --- | --- |
| Startup | AX returned application objects in its window list with a successful API status. Sillies incorrectly classified this as a verified list with no usable windows. | Decode only real window objects with readable, finite geometry. Unavailable reads retain previous verified roles; startup can use the existing normal-window fallback. | Reproduced against the live native API using the production reader; malformed-value, minimized/modal and cached-role regressions. |
| Semantic search | A small disk index could miss candidates outside the nearest 96 trained partitions. | Search every partition when encoded vectors and IDs fit a 32 MiB scan budget. Larger indexes retain 96 probes and 256 reranking candidates. | Same 433-query corpus for Apple and E5; reopen/deletion regression; million-vector candidate parity. |
| Chat | Reopening the same companion while its last save was finishing could fail activation. | Wait for the existing session to finish through the owned, cancellable navigation request. | Held final save, draft restoration and stop-before-reopen tests. |
| Vault evidence | Link search extracted URLs only from old Stash text, dropping newer link records whose URL lived in metadata. | Search and record reading use the canonical saved URL, with Stash extraction as fallback. | Website, video and social-post records; changed notes, Trash/restore and bounded header-only link reads. |
| Model setup | A failed installation-state read could leave a partial catalog that prevented retry. | Stage the entire catalog before publication; join concurrent loads and reject stale completions. Text, voice and search settings offer Try again on discovery failure. | Corrupt installation receipt followed by recovery; cancellation, joined loads and restart tests. |
| Runtime lifecycle | Independent pause/resume tasks could overlap teardown with wake. | One app-owned coordinator serializes text, voice and search activity, coalescing intermediate requests. Settings stop only their own operations. | Held teardown/wake, 2,000 rapid state changes, final shutdown and cancelled-quit resume tests. |

## Semantic-index comparison

The frozen corpus has 5,247 documents, 19,354 prepared passages and 433 queries. It combines the pinned
SciFact distribution with authored everyday, multilingual, filtering and missing-evidence cases.
The [preceding report](vault-search-refinement-2026-11-08.md) describes its limits and provenance.
No source text from the personal Vault was used.

| Provider | Exact top-five overlap before → after | Available queries | Semantic median before → after |
| --- | --- | --- | --- |
| Apple contextual embeddings | 99.245% → 100% | 427 / 433 | 17.21 → 18.62 ms |
| Multilingual E5 small | 96.837% → 100% | 433 / 433 | 12.27 → 13.67 ms |

“Overlap” measures agreement with canonical full-vector ranking, **not answer accuracy**. Its
nonempty-reference denominator is 424 queries for Apple and 430 for E5. Apple's six unavailable
queries remain counted and reflect missing native language assets on this Mac. There were no
reported transport errors or deadlines in these final runs. SQ8 quantization remains approximate;
100% observed agreement on this corpus is not a guarantee for other libraries.

The latency figures include the benchmark's semantic retrieval operation and use available queries.
Each provider has one completed run per condition, on an Apple M4 Pro with 48 GiB memory. They establish
the coverage/latency tradeoff, not a universal speed claim. First samples are retained and are not
controlled cold starts. Raw timings and nearest-rank p95 values are in the
[comparison data](data/app-acceptance-2026-11-08/comparison.json).

At one million synthetic 384-dimensional vectors, alternating 96-probe reference and production runs
returned identical 256-candidate sequences for 100 queries per run. Median times were 31.87 / 30.86 /
30.28 / 29.78 ms in reference / production / reference / production order. This supports unchanged
large-index behavior; the small differences are not claimed as a speedup.

### Rejected exact-search experiments

Broad Best match still ranks all matched blocks and is the expensive path at million-record scale.
Two system-SQLite experiments matched the baseline’s first-page ID/score fingerprint:

| Experiment | Repeated million-record time | Decision |
| --- | --- | --- |
| Materialize block ranks before grouping | Baseline 3.51 s; experiment 5.13 s | Rejected: slower once warm. |
| Skip an empty pending-cleanup exclusion | Baseline 3.44–3.47 s; experiment 3.17–3.24 s | Not shipped: modest gain would duplicate visibility-sensitive query policy. |

These short-record fixtures and bounded SQL probes do not establish performance for a million long
meetings. First samples, including a 13.66-second baseline, are retained in the raw data. No candidate
cap or approximate keyword ranking was introduced to improve the numbers.

The [follow-up ranking and preview qualification](vault-rank-boundary-2026-11-08.md) records the later
exact-bound optimization and indexed excerpt lookup, with new release measurements and regressions.

## Validation and limits

Focused checked runs passed for search (6 selected tests), workflows (21), Vault evidence (18), model
setup (13), and interruption/recovery (54). Startup's first focused run passed four tests. Completion
receipts establish the selected tests actually finished; counts can overlap between runs.

`make check` passed: 1,063 selected Swift/XCTest tests across 21 checked runs,
architecture/localization checks, catalog validation, packaged GPU/helper checks and helper parent-exit
checks. `make stress` passed 298 selected tests across 13 checked runs. `make race-check` passed 348 selected tests across 16 checked runs with no reported races. All 127
Python tests passed after the final runner-batching regression was added.

The first full run exhausted the runner's shared 180-second execution deadline while reaching the
10,000-memory fixture. That case completed independently in 12.16 seconds. The default test command
now gives native app workflows and reusable modules two disjoint runs with the existing deadline;
all discovered test completion requirements remain. The first race run similarly reached its shared
90-second deadline after completing its app checks. Its native, voice and remaining-module groups now
run separately under that unchanged limit. Workflow regressions check that current and future
bundles/tests belong to exactly one batch. No performance assertion was relaxed.

The fixed signed development app was installed and launched normally, without the temporary
`--without-accessibility` argument. Native on-screen enumeration confirmed all four configured
companion windows. The original malformed AX response still reproduced during that verification,
so the fix did not depend on the external API recovering.

Native startup inspection is limited to the user's reported failure and the replacement app launch.
The broad visible GUI suite was not requested and is not part of this pass. Headless checks do not
prove every keyboard, stacking or animation interaction. Retrieval validation does not replace
LLM answer-quality evaluation, and the published model rankings are unchanged.

The malformed AX response explains why Sillies hid the crew; it does not establish why the user's
macOS session restarted. No companion preference reset or permission reset is part of the fix.

[Raw evidence and reproduction notes](data/app-acceptance-2026-11-08/README.md).
