# Vault search: coverage, exact-ranking experiments and multilingual validation

Follow-up to the [November 7 qualification](vault-qualification-2026-11-07.md).
The baseline is commit `d5a5dcf5dc0ec33f6de1ba952ea040606cc59749`. This work uses disposable
libraries and release inference helpers; it does not read or modify the personal Vault.
Machine: Apple M4 Pro, 48 GiB memory, macOS 26.7.2. Runs share the working machine with other apps.

## What changed

| Area | Retained change | Outcome |
| --- | --- | --- |
| Embedding capacity | Shared, bounded input preparation using each provider's actual token capacity | Previously oversized passages receive complete-input embeddings |
| Coverage in Settings | Show searchable vectors against prepared passages, with a keyword-only explanation | Index completion no longer suggests every passage is semantically searchable |
| Scoped semantic search | Use the canonical workspace filter during ranking and result materialization | Explicit Trash searches work; ordinary searches and assistant retrieval still exclude Trash |
| Timeout classification | Preserve native transport deadlines as typed search timeouts | Keyword fallback remains available without a misleading generic interruption error |
| Qualification | Add 98 authored queries, evidence checks and explicit oracle availability | Unsupported outcomes and missing information remain visible in scores |
| Exact Best match | Keep the existing aggregate query | The replacement and larger-cache experiments did not justify a product change |

**Broad Best match latency at one million records remains unresolved.** This report does not claim
an exact-search speed improvement or unrestricted scale. It records the rejected experiments as well
as the retained fixes.

## 1. Provider-aware input preparation

Canonical Vault passages remain bounded to 1,200 Unicode scalars with stable source locations.
That is not a tokenizer budget: Apple's API exposes a
[token sequence limit](https://developer.apple.com/documentation/naturallanguage/nlcontextualembedding/maximumsequencelength),
and E5 also counts its purpose prefix and special tokens.

`EmbeddingPreparation` delegates capacity detection to the adapter. When input does not fit, it
splits at a nearby whitespace/character boundary, preserving all characters, and combines raw means
weighted by their actual token counts. Normalization happens once at the end. It never publishes a
supported prefix as the embedding for a partially unsupported input. This is windowed mean pooling;
it does not claim to reproduce attention across a sequence longer than the model can accept.

Apple resolves language on the full input so a short continuation does not independently switch
language/model space. Both providers include the preparation revision in their identities. Existing
lifecycle owners rebuild derived vectors in the background; source records and passage references
remain intact. Cancellation and a finite byte/attempt budget bound preparation. Exhausting the
capacity budget produces an unsupported outcome, leaving keyword search available instead of
stopping the index job. Invalid vectors or mixed spaces remain errors.

### Frozen-corpus comparison

The unchanged November 7 corpus contains 5,198 documents, 335 queries and 19,198 passages.
The preparer was rerun and its original input and expectation files compared byte for byte.

| Provider | Searchable passages before → after | Scientific hit@5, exact vectors | Everyday hit@5, exact vectors |
| --- | ---: | ---: | ---: |
| Apple, installed assets | 16,131 → **19,192 / 19,198** | 46/300 → **49/300** | 11/12 → **10/12** |
| Multilingual E5 small | 19,192 → **19,198 / 19,198** | 226/300 → **226/300** | 12/12 → **12/12** |

Apple recovered all 3,061 previously capacity-limited passages. Six unsupported/undetected-language
outcomes remain. E5 recovered all six oversized passages. These are coverage gains, not a claim that
mean pooling makes every query more relevant.

The Apple everyday regression was investigated: the recovery-exercise document was fifth for
“How do we verify our backup can actually be restored?” A newly searchable scientific passage
about thawing frozen analysis displaced it. Exact-vector ranking reproduces the change, so it is
not an approximate-index omission. No query-specific exclusion or relevance threshold was added.
E5's exact scores were unchanged across the frozen groups.

The full result rows, coverage identities and scores are in
[data/vault-search-refinement-2026-11-08](data/vault-search-refinement-2026-11-08).
The prior report retains the original baseline result sets.

## 2. Exact Best match experiments

The million-record fixture still contains short synthetic records: 5 million content blocks,
4 million FTS entries and an approximately 8.96 GB SQLite file. A second fixture contains 100,000
records with random UUIDs, rather than identities ordered by insertion. `seed-random` is now available
in `VaultScaleBenchmark` to repeat this check with the same content distribution.

The main prototype read passages in FTS rank order and retained at most 101 candidate documents.
It evaluated record filters only when a candidate could enter that set, exhausted tied scores, and
fell back to the complete aggregate query after a bounded number of eligibility reads. Continuation
pages kept full document aggregation so weaker passages could not reintroduce earlier records.
Correctness checks covered ties, filters, best passages and cursor pages. Nevertheless, it was slower:

| Fixture | Existing query median | Ordered prototype median | Decision |
| --- | ---: | ---: | --- |
| 100,000 records, random IDs | **842.54 ms** | 981.39 ms | Reject |
| 1,000,000 records, ordered IDs | **4,420.88 ms** | 5,536.32 ms | Reject |

Each complete release run used 15 samples. Run order was fixed, on a shared working Mac; filesystem
cache and unrelated activity were not controlled. These are rejection evidence, not a claim that
the old 3.71-second measurement regressed. The prototype's earlier exploratory million-record
median was 5.71 seconds. First samples must not be described as controlled cold starts.

A native sample placed the initial expensive section inside SQLite's FTS BM25/document-size lookup
and page-cache work. The Swift result loop was not the sampled bottleneck. An isolated probe linked
to the same macOS SQLite 3.51.0 tested 2,000, 16,384 and 65,536 KiB caches, then repeated 2,000 KiB.
There was no consistent gain: warmed observations stayed roughly 3.3–4.5 seconds. Cache limits were
not raised. Python-only SQL experiments were treated as exploratory because they do not necessarily
use the same SQLite implementation as the app.

Other discarded approaches included ordering after full metadata joins and a bounded candidate
range with a global-rank proof. They added traversal or repeated scoring work. No candidate cap,
approximate keyword ranking, result-cache benchmark shortcut or memory-mapped database policy was
introduced. SQLite documents both the possible benefit and the uncaught I/O failure trade-off of
[memory-mapped database reads](https://www.sqlite.org/mmap.html); that trade-off was not added here.
The prototype implementation was removed from product sources.

## 3. Expanded retrieval suite

The optional `multilingual.json` extension adds 49 documents and 98 queries to the frozen corpus:
**5,247 documents, 433 queries and 19,354 passages** in total.

| Group | Queries | What it checks |
| --- | ---: | --- |
| Native phrasing | 22 | A distinct local event in every app language |
| Paraphrases | 22 | Different wording for the same explicitly documented fact |
| Cross-language questions | 22 | English questions about each language's source document |
| Absent details | 22 | A related event exists but the requested private detail does not |
| Late evidence | 6 | Supporting details beyond multiple canonical passage boundaries |
| Scoped evidence / absence | 4 | Active records, Trash, tags and empty eligible sets |

Each language has its own event, budget and nearby distractor; these are not 22 translations of one
fact with incomplete relevance labels. Supporting quotes must occur in the identified source.
Related-but-insufficient annotations are separate from supporting IDs. Query labels, groups, quotes
and language annotations are removed from native worker inputs.

These are **authored regression cases**, not independently adjudicated language benchmarks.
They share a narrow community-event/budget pattern and can overrepresent entity matching. The English
case in the cross-language group is an English control. The independently labeled SciFact subset
remains unchanged. Neither set establishes universal relevance or a default for every personal Vault.

### A product bug found by the new suite

Both providers initially missed the positive Trash case, while keyword search found it. The semantic
reader combined an explicit Trash filter with an unconditional `trashed IS NULL` condition. This was
an integration bug, not a model failure. The reader now applies the shared workspace scope in both
ranking and materialization, including tag/category revalidation. A regression covers ordinary
assistant exclusion, explicit Trash/tag search with native candidates, restoration and empty scopes.

### Final scores

Both final runs completed all 433 queries after the build/test workload stopped. E5 was ready for
433/433. Apple was ready for 427/433; the six unavailable queries were the native, paraphrase and
absent-detail Russian/Ukrainian cases without installed Cyrillic assets. These remain in the
denominators. Neither final run recorded a timeout or processing failure. Final passage coverage was
19,338/19,354 for Apple and 19,354/19,354 for E5.

The cells below count queries with supporting evidence in the first five documents. Parentheses
show the **exact-vector oracle**, which uses the same embeddings without approximate candidates.

| Query group | Keyword search | Apple index (exact) | E5 index (exact) |
| --- | ---: | ---: | ---: |
| SciFact, 300 | 226 | 49 (49) | 226 (226) |
| Original everyday, 12 | 10 | 10 (10) | 11 (12) |
| Original cross-language, 3 | 0 | 0 (0) | 1 (1) |
| Original filters, 14 | 13 | 14 (14) | 14 (14) |
| Native phrasing, 22 | 19 | 20 (20) | 22 (22) |
| Paraphrases, 22 | 19 | 19 (20) | 22 (22) |
| Expanded cross-language, 22 | 16 | 1 (1) | 18 (18) |
| Late evidence, 6 | 5 | 2 (2) | 6 (6) |
| Active/Trash scoped evidence, 2 | 2 | 2 (2) | 2 (2) |

Average overlap with the oracle's top five was 99.25% for Apple and 96.84% for E5, over respectively
424 and 430 queries with nonempty oracle results. Those averages do not eliminate meaningful misses:
the Apple index missed the Czech paraphrase's supporting document, ranked second by the oracle;
E5 missed the original German everyday document, ranked first by the oracle. These are approximate
candidate-selection misses, not embedding failures. Index search parameters were not fitted to
these cases. The raw rankings and full recall/MRR/nDCG scores remain in the evidence bundle.

None of the three empty-filter cases returned a result. On the 22 absent-detail questions,
keywords returned suggestions for 19, Apple for 20, and E5 for 22. All five original absent-information
cases also returned suggestions. A related document is not sufficient evidence for an answer;
these results do not establish reliable abstention by an answering model.

| Final production semantic path | Median | p95 | Maximum |
| --- | ---: | ---: | ---: |
| Apple | 17.17 ms | 45.24 ms | 225.81 ms |
| E5 | 12.27 ms | 25.01 ms | 81.82 ms |

These are per-query measurements on the 5,247-document corpus after index preparation, including
unavailable outcomes. They exclude model download, indexing and UI presentation. The benchmark
requests 20 candidates before reporting five; this is not a full assistant or end-to-end UI latency
measurement. p95 uses nearest rank. There is one completed final pass per provider, not a repeated hardware comparison.
E5 is stronger on this corpus, particularly across languages; its original three cross-language
cases still score only 1/3. The authored extension alone is insufficient to choose a universal default.

One verification run overlapped the full build/test workload. Apple's production search recorded
402 ready queries, 30 unavailable outcomes and one processing failure; the separate oracle also
recorded a processing failure. Investigation identified the two-second transport deadline:
a timed-out `poll` was incorrectly classified as interruption. The generic wire now
distinguishes timeout from EOF, and the embedding adapter maps it into the feature's typed timeout.
The existing helper eviction/warmup behavior remains; deadlines were not lengthened. The complete
contended results are retained, including failures and subsequent temporary keyword fallback.
The final comparison above ran after build work stopped; it does not erase that failure evidence.

The exact-vector oracle separates model relevance from approximate-index fidelity. Related
suggestions for absent-detail queries are counted, but are not classified as generated hallucinations:
this benchmark retrieves documents and does not generate answers. Diagnostic rank fusion is also
reported separately from the workspace's visual ordering.

## 4. Validation and reproducibility

`make check` passed, with verified completion of **1,052 selected Swift tests across 21 runs** and
**125 Python tests**. This includes the 13 retrieval-scoring tests, complete-input pooling and
cancellation tests, explicit Trash/restoration regression, native pipe deadline/EOF checks, and
a stalled-helper timeout/recovery test. Architecture checks, Swift formatting, all 22 language
catalogs, localization extraction, inference GPU smoke checks, helper parent-exit checks and
catalog validation passed. The release helper and benchmark executable were frozen before the
final Apple/E5 runs; input and executable hashes are retained in their receipts.

The scorer's independent arithmetic tests cover graded relevance, the top-five cutoff, full positive
denominators, missing/duplicate/filtered results, valid timings, explicit unavailable oracle outcomes,
and supporting-versus-related annotations. An unavailable oracle counts as a miss; a missing oracle
measurement still rejects the run. All nine previously published result files rescore unchanged;
the replay receipt is included.

Run instructions and attribution remain in [Benchmarks/Vault](../../Benchmarks/Vault/README.md).
SciFact is by Wadden et al., distributed through BEIR; abstracts are ODC-By 1.0 and claims/evidence
labels CC BY 4.0. Downloaded abstracts are not committed here. Published input/executable hashes,
coverage and result rows identify the runs. Benchmark invocations use resumable 20-second slices and
bounded child-process watchdogs. This work adds no multi-hour soak requirement or Python runtime to
the app. Native window presentation was not changed or rerun; this round's app checks are headless.
