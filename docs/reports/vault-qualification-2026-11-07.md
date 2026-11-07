# Vault search, lifecycle and native interaction qualification

**7 November 2026 · Apple M4 Pro, 48 GiB · macOS 26.7.2**

This follow-up covers the four remaining items from the
[workspace report](vault-workspace-2026-11-07.md). Changes were measured against disposable fixtures
using the application APIs. No personal Vault records were read, changed or removed.

## Outcome

| Area | Completed work | Important limit |
| --- | --- | --- |
| Broad Best match | Covering metadata index and streamed FTS scores; exact ranking, filtering and pagination preserved | Million-record median is **3.71 s**; the first measured sample was **14.14 s**. This is still a slow query. |
| Semantic retrieval | 5,198 documents, 335 queries, real Apple/E5 embeddings, independent relevance labels and exact-search comparison; improved native candidate retrieval | Index fidelity is much better. Model relevance, absent-information handling and passage coverage remain separate limitations. |
| Library lifecycle | Completed million-record backup, restore and deletion; 1,000 long-meeting fixtures with files; interrupted index recovery | The million-record fixture has short records. It is not one million full meetings or recordings. |
| Native interaction | Unlocked keyboard focus, Cmd+C, close/reopen, actual window stacking, resize and scroll checks | One Mac, short native runs. These do not establish hitch-free presentation on every display. |

The production changes are focused: schema-4 indexes, the exact relevance query, batched backup file
enumeration, and a higher bounded native-index probe count. No candidate cap was added to keyword
ranking. The tests and qualification tools have separate responsibilities from application behavior.

## 1. Exact keyword search

The scale fixture contains **1,000,000 records, 5,000,000 content blocks and 4,000,000 FTS entries**.
Its SQLite file is 8.96 GB. Measurements use release builds, 15 samples per query, median and
nearest-rank p95; with 15 samples that p95 is the maximum.

| Operation | Median | p95 / maximum | Source bodies decoded |
| --- | ---: | ---: | ---: |
| Recent items | 1.43 ms | 2.94 ms | 0 |
| Broad search, newest first | 132.97 ms | 201.15 ms | 0 |
| Recently edited | 1.37 ms | 2.14 ms | 0 |
| Broad search, Best match | **3,705.09 ms** | **14,137.09 ms** | 0 |
| Rare term | 0.20 ms | 3.11 ms | 0 |

The previous report recorded a 5,402 ms broad-search median and a 42,076 ms first sample. The new
median is about 31% lower. This is a historical comparison, not a controlled cold-cache A/B result:
filesystem cache and background load were not held constant. The first sample must not be called
a qualified cold-start measurement.

Two sources of unnecessary work were removed:

1. Relevance filtering now uses a covering index rather than fetching pages containing large source
   bodies for every matched document. Ordinary detail/date reads retain their own index choices.
2. FTS scores stream into document grouping instead of materializing the entire matched-block set
   first. The unlimited `LIMIT -1` boundary prevents an invalid flattened FTS aggregate without
   dropping candidates. SQLite documents the relevant
   [flattening and co-routine behavior](https://www.sqlite.org/optoverview.html).

Tests compare all result pages, filters, excerpts and best-block identities with the preceding exact
query. Both visibility views share the same deletion/retention predicates. Schema migration and
read-only access to the preceding backup format are covered.

During a broad search, independent document reads measured **0.039 ms median / 2.895 ms p95**;
a save took **8.04 ms**, cancellation acknowledged in **9.65 ms**, and the reused reader returned
the next page in **1.81 ms**. These are application/storage timings, not total keystroke-to-paint latency.

**Remaining constraint:** exact broad relevance still groups and ranks the full matching set.
Subsecond broad ranking at this size is not established. Returning a capped subset would change
correctness; that shortcut was not retained.

## 2. Real semantic retrieval

### Corpus, scoring and coverage

The frozen corpus combines the public **BEIR SciFact test split**—5,183 abstracts and 300 independently
annotated queries—with 15 authored everyday documents and 35 regression queries. It produces
**19,198 candidate passages**. Gold labels are kept outside the native retrieval process.

The added cases cover everyday retrieval (12), filters (14), cross-language retrieval (3), absent
information (5), and a filter matching no documents (1). Filter cases include unrelated and trashed
distractors in the larger corpus, but most eligible filtered subsets are small. They are functional
coverage, not a million-document filtered-relevance study.

The scorer rejects missing/duplicate queries, unknown or filtered-out results, excess results,
invalid grades/times and incomplete exact comparisons. Eight independent tests include hand-calculated
metrics, failures retained in denominators, absent-query reporting and a missing-oracle regression.
All nine published baseline, 64-probe and 96-probe result sets were rescored unchanged after this audit.

| Provider | Nonempty passage vectors | No-vector passage outcomes | Scientific hit@5, exact search |
| --- | ---: | ---: | ---: |
| Multilingual E5 small, pinned revision `614241f622f53c4eeff9890bdc4f31cfecc418b3` | 19,192 | 6 | 75.3% |
| Apple contextual embeddings, installed native assets | 16,131 | 3,067 | 15.3% |
| Keywords | Not applicable | Not applicable | 75.0% |

“Indexing complete” means every passage received an outcome; it does not mean every passage has a
usable vector. The run metadata records actual provider/space identities and coverage, including
empty outcomes. Apple uses Sillies' mean pooling of native contextual token vectors; these numbers
describe that integration and this mostly scientific corpus, not an intrinsic ranking of every use
of Apple's models. E5 also rejects inputs that exceed its tokenizer limit rather than embedding only
a prefix. Keyword retrieval remains available for those passages.

Apple's documented limit is in subword tokens, not characters; its API truncates oversized inputs.
Sillies rejects limit-reaching results to avoid representing a truncated passage as complete. A fixed
character-sized passage can therefore exceed a provider's token budget.
[Apple's sequence-limit contract](https://developer.apple.com/documentation/naturallanguage/nlcontextualembedding/maximumsequencelength)
explains why passage coverage must be measured independently of index completion. Provider-aware
passage preparation needs its own measured qualification before changing these semantics.

A separate native replay of all 3,067 empty Apple outcomes identified **3,061 reaching the installed
model's 256-token limit**, four detected languages without available support, and two inputs with no
detected language. None became embeddable on replay. Thus most of this coverage loss is a mismatch
between our passage sizing and the native model's limit, not evidence that Apple cannot understand
those documents. Removing the truncation check would hide the problem; it was not removed.

Dataset attribution: Wadden et al., *Fact or Fiction: Verifying Scientific Claims*, EMNLP 2020;
[SciFact](https://github.com/allenai/scifact), distributed through [BEIR](https://github.com/beir-cellar/beir).
Abstracts are ODC-By 1.0; claims/evidence labels are CC BY 4.0. See the
[dataset license](https://github.com/allenai/scifact/blob/master/LICENSE.md).
Downloaded abstracts are not committed. Published query labels retain this attribution.

### Native index fidelity

The exact oracle uses the same provider, persisted vectors, filters and application API with native
approximate candidates disabled. Thus this comparison isolates index misses from embedding relevance.
Agreement means mean overlap with the exact top five, not recall against the gold relevance labels.

The baseline searched 24 IVF partitions. We tested 64, then 96. The qualification target was at least
95% exact-top-five overlap in each measured index condition while retaining bounded query work.

| Provider / index condition | 24 partitions | 64 partitions | Retained: 96 partitions | Related-search median / p95 at 96 |
| --- | ---: | ---: | ---: | ---: |
| E5, grown index | 87.5% | 97.5% | **99.6%** | 12.80 / 21.28 ms |
| E5, fully rebuilt index | 84.2% | 93.9% | **97.2%** | 13.36 / 78.29 ms |
| Apple, grown index | 98.4% | 100.0% | **100.0%** | 16.71 / 27.86 ms |

The grown E5 index was trained earlier in ingestion with 128 partitions; rebuilding from the completed
corpus used 256. Both conditions matter because users' indexes grow and recover over time. The higher
probe count applies both when creating and opening an index. Candidate count remains at most 256,
with two compute workers and one disk-prefetch worker. No model-specific relevance cutoff was fitted.
Faiss describes this accuracy/work tradeoff in its
[IVF index documentation](https://github.com/facebookresearch/faiss/wiki/Faiss-indexes).

All 335 query operations returned `ready` in the final runs. The empty-filter query has an empty exact
set; it remains counted as a query but contributes no overlap denominator. There are 334 overlap
comparisons per run.

| Case group | Keywords | E5, grown index at 96 | Apple at 96 |
| --- | ---: | ---: | ---: |
| Scientific, 300 queries: hit@5 | 75.0% | 75.3% | 15.3% |
| Everyday, 12 queries: hit@5 | 10/12 | 12/12 | 11/12 |
| Filters, 14 queries: hit@5 | 13/14 | 14/14 | 14/14 |
| Cross-language, 3 queries: hit@5 | 0/3 | 1/3 | 0/3 |
| Absent information: suggestions returned | 5/5 | 5/5 | 5/5 |
| Filter with no eligible records: suggestions returned | 0/1 | 0/1 | 0/1 |

E5's rebuilt index finds 11/12 everyday cases. Scientific hit@5 is 75.3% in both index conditions,
up from 71.3% and 69.7% with 24 probes. This demonstrates an integration improvement without claiming
the approximate index is exact.

Absent-information cases are deliberately visible: related suggestions do not establish that a
requested fact exists. The tiny multilingual/negative sets cannot justify a universal confidence
threshold. There is no claim here that Apple or E5 is the best provider for every personal library.
The public corpus may also have appeared in model training; no contamination-free claim is made.

The raw files include a diagnostic rank-fusion comparison. That merges two top-20 lists with the
existing fusion policy; it is **not** the workspace's visual ordering or a full assistant evaluation.
On SciFact, diagnostic fused hit@5 is 75.7% for E5 and 65.7% for Apple, versus 75.0% for keywords.
Blindly treating all semantic candidates as better evidence would be unjustified.

### Million-vector cost check

A separate fixed, clustered **synthetic** million-vector index was queried 100 times per setting,
interleaving 24, 64 and 96 probes. Its median native search cost was approximately **7.6–7.8 ms**,
**20.0 ms**, and **29.6–29.7 ms**, respectively; the 96-probe p95 was **31.4–31.6 ms**.

This prototype used the existing local Faiss experiment and its Homebrew OpenMP linkage. It is a
budget check, not product-runtime or real-corpus latency evidence. The real-embedding runs above used
the application's native helper with the vendored runtime. The synthetic corpus is favorable to
clustering; it does not establish quality at one million real embeddings.

## 3. Backup, restore, deletion and recovery

### Completed operations

| Fixture | Backup | Restore preparation | Next-launch activation | Verified |
| --- | ---: | ---: | ---: | --- |
| One million short records, no attachments | 31.51 s, before the final attachment-query fix | **141.34 s**, final query | 3.94 ms | Record count; complete source/section content for 20 sampled records |
| 1,000 long synthetic meetings | 1.76 s | 2.07 s | 3.93 ms | Record count; all 1,000 files byte-for-byte; source/section content for 20 sampled records |

The long-meeting fixture has 300 transcript turns per record, roughly 60 KB of text, plus a 64 KiB
deterministic binary attachment. Attachments test storage/copy/deletion, not recording playback.
The samples are the first and last ten records, with every section page compared. This is sampled
content verification, not a hash comparison of every million-record body.

The first million-record restore exceeded a 240-second process watchdog. It was retained as a failed
run. Inspection showed installation had completed; attachment verification also exposed an inefficient
query. The revised query merges two ordered partial-index streams and skips fileless records. The
empty attachment walk dropped from approximately 20.64 s to 16.52 ms in resumed verification.
Backup cursors also reject noncanonical stored identifiers: normalizing a damaged ID during paging
could otherwise revisit the same record. A regression exercises that failure input.

A separate fresh full restore then completed in **141.40 s process time**, within a 180-second watchdog.
Sampling showed SQLite's full backup integrity scan dominated preparation. Integrity validation was
not removed to obtain a faster result. This remains an explicit background file operation, not a
per-navigation cost. Routine tests cover cancellation, interrupted activation and preserved originals.

| Completed deletion | Initial clear commit | Resumed drain processes | Total process time, including clear | Page reads while draining: median / p95 |
| --- | ---: | ---: | ---: | ---: |
| One million short records | 54.95 ms | 40, each bounded to about 20 s | 808.95 s | 0.044 / 0.064 ms |
| 1,000 long meetings and files | 75.46 ms | 1 | 11.36 s | 0.038 / 0.070 ms |

Cleanup was explicitly completed, not inferred from an empty visible list. Independent SQLite reads
confirmed zero canonical records, blocks, search rows, vectors, pending deletions, cleanup jobs and
attachment-journal rows. The meeting fixture had zero remaining attachment files. The million-record
database returned no matching search results and passed `PRAGMA quick_check` after cleanup.

The SQLite file does not shrink immediately: freed pages remain available for reuse. This is logical
deletion and file unlinking, not a forensic secure-erasure or automatic-vacuum guarantee.

### Interrupted indexing

The disposable retrieval process and its owned helper were terminated while a native write marker
was present. Canonical passage outcomes remained at 19,198. Restart rebuilt the derived index in
**3.05 s**, and all 335 retrieval queries were rerun. The recovered E5 index was also included in both
probe-count experiments above. Existing tests cover stale/deleted candidates, provider replacement,
invalid native buffers and checkpoint lifecycle failures.

No multi-hour blocking soak was used. Seed, indexing and cleanup work resume in short slices;
complete backup/restore operations have external watchdogs and can be monitored asynchronously.

## 4. Native behavior and validation

On the unlocked desktop, four native tests passed:

- Cmd+F moves focus from the document editor into search; typing there does not alter the document.
  Hiding/reopening preserves the same window, editing state and key-window behavior.
- Cmd+C follows the native responder chain and copies selected text.
- Foreground content covers normal mascot overlays while remaining below native floating windows.
- Resize/scroll operations preserve a usable native text viewport.

The resize probe performs 48 aggressive size/scroll operations, including resets between sweeps.
Operation timing was **6.94 ms median / 18.15 ms p95 / 20.15 ms maximum**. Display-link intervals were
**16.67 / 25.01 / 33.34 ms**. These include AppKit layout and are not GPU presentation timestamps.
They establish exercised native behavior, not an assertion that every frame stays within 16.7 ms.

The actual `--app-window-test` passed the menu popover → Settings/Vault/Chat sequence, activation,
close/reopen, own-window exclusion and foreground/background stacking. Its obsolete assertion that
ordinary content must cover floating-window companions was corrected to match the documented native
layering policy; the separate stacking tests retain the floating-window constraint.

An initial locked-desktop run was not counted. The GUI test launcher now reports that condition
explicitly instead of treating unavailable focus as an application failure. Routine `make check`
continues to run headlessly; visible native checks are opt-in.

Final validation passed `make check`: **1,041 selected native tests across 21 runs**, **120 Python
tests**, architecture/import checks, formatting, localization, pinned-vendor verification, catalog
validation, helper self-tests and helper parent-exit checks. The subsequent scorer audit passed eight
focused tests and reproduced the published scores. The native fixture also uses the checked native
window-identifier boundary. That final test-helper change compiled; its optional GUI rerun was refused
because the desktop had locked again. Native evidence above comes from the earlier unlocked run,
not from that refused rerun. No production UI behavior changed between those runs.

## Reproduce and inspect

- [Qualification tools, procedures and dataset attribution](../../Benchmarks/Vault/README.md)
- [Raw scores, per-query results and timing samples](data/vault-qualification-2026-11-07/)
- [Run summary, model identities, coverage and failed runs](data/vault-qualification-2026-11-07/run-summary.json)
- [Baseline workspace report](vault-workspace-2026-11-07.md)
- [Vault architecture and extension guide](../contributing/vault.md)

The source baseline was `9ed7df2abdb9a9e766677c647c78831c57270ae3`; these results include the changes
in this qualification increment. Executable and input hashes are retained with retrieval receipts.
Only disposable fixture paths were redacted in published lifecycle files. Earlier resumed-verification
files contain zero placeholders for unmeasured preparation/activation; they are not zero-time restores.
The tool now omits those unmeasured fields.

## Remaining limits

1. Broad exact relevance needs further algorithmic work to become consistently subsecond at one million
   matching records. UI isolation and cancellation are verified; instant completion is not.
2. Provider-aware passage preparation and explicit coverage reporting deserve a separate increment.
   Apple currently leaves more candidate passages without vectors on this corpus. Approximate-index
   fidelity cannot fix those missing embeddings or the model's relevance limitations.
3. Absent-information calibration needs a larger independent set. Suggestions must remain distinguishable
   from evidence that a particular requested fact exists.
4. One million real embeddings, full-length recording storage, other Macs/displays and longer native
   interaction sequences remain outside this qualification. The fixtures and tools make those runs
   resumable; these results do not establish unlimited capacity or universally flawless rendering.
