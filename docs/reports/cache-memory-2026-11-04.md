# Cache, first-message latency and saved memories — 4 November 2026

This follow-up starts at `8716a94`. It investigates native cache coverage, first-message preparation,
retrieval at realistic memory counts and revision-safe writes. The
[registration](../../Benchmarks/Chat/experiments/cache-memory-2026-11-04/study.json) fixes a separate
1,200-second native-execution budget, sequential bounded batches, synthetic stores and unchanged
quality rubrics. All measurements use one M4 Pro Mac with 48 GiB RAM. No model downloads or user
records are involved.

## Native cache coverage

The existing production helper was tested before changing either profile. Ten matched follow-ups
per model use five frozen fact questions twice, alternating retained/rebuilt order. Token measurement
precedes generation and streamed deltas are acknowledged. Sampling is temperature zero in these
protocol probes; product sampling is unchanged. The control omits session identity. All forty
answers match their expected exact values.

| Warm follow-up first text, median | Rebuilt | Retained |
| --- | ---: | ---: |
| Granite 4.2 3B | 2.132 s | 0.104 s |
| Ministral 3 8B | 5.136 s | 0.226 s |

Granite reuses 2,026 prompt tokens; Ministral reuses 1,868. Nine controls pass for each model:
unchanged history, edited history, changed instructions, changed tools, changed session identity,
current-session end, unrelated-session end, context rejection and generation failure. Only unchanged
history and ending an unrelated session preserve reuse. Context checks and teardown remain active.
These are warm follow-up diagnostics, not full-task leaderboard replacements or cross-hardware
latency guarantees. Profiles select the existing native-session abstraction; no model-name branches,
manual recurrent-cache trimming or dependency changes are added.

## First-message preparation

Each of two repetitions starts a new helper, observes a no-load control response, measures the input,
and generates an opening reply. A second generation uses a new session identity with the same loaded
model. The input contains roughly 1,900–2,000 tokens, including app instructions and tool definitions.
Operating-system file and kernel caches are not flushed: process-cold does not mean machine-cold.

| Stage, observed range | Granite 3B | Granite 8B | Ministral 8B |
| --- | ---: | ---: | ---: |
| Helper start to control receipt | 30–31 ms | 33–36 ms | 34–35 ms |
| Native model loading | 0.375–0.379 s | 0.671–0.823 s | 0.930–1.380 s |
| Tokenizer setup, overlapping loading | 0.228–0.249 s | 0.240–0.241 s | 0.670–0.707 s |
| Initial input rendering/tokenization | 34–35 ms | 34–36 ms | 51 ms |
| Native prompt processing | 2.136–3.428 s | 5.200–5.303 s | 4.687–4.730 s |

Tokenizer work runs in parallel with native weight loading inside the SDK. Its time must not be
added to loading or subtracted to claim isolated weight I/O time. Native prompt timing includes work
attributed to prefill by the runtime; these probes do not isolate shader compilation. The existing
exact tokenization cache reduces the generation request's repeated input preparation to about
0.1 ms. The helper is already retained while the conversation lifetime and memory budget allow it.

The measured repeated cost is native prompt processing, which continuation removes on supported
follow-ups. No additional speculative warming or custom prefix-cache implementation is promoted.
The optional, content-free preparation observer remains available through `--inspect-generation`;
normal application inference does not log these spans or conversation content.

## Memory retrieval and storage

The old store capped saved facts at 200 and ordered all matches by recency before the tool selected
four. The new query ranks FTS5 relevance before recency, limits identities before decoding bodies,
and runs on the independent read-only search worker. Memory changes invalidate in-flight memory
searches without invalidating unrelated conversation searches. Empty queries still mean recent facts.
The source is SQLite's [FTS5 ranking contract](https://www.sqlite.org/fts5.html#sorting_by_auxiliary_function_results).
This is lexical retrieval, not a semantic embedding or multilingual paraphrase guarantee.

| Synthetic saved facts | Relevant facts in top four, old ordering | Ranked ordering | Slowest of eight queries |
| --- | ---: | ---: | ---: |
| 200 | 0/8 | 8/8 | 0.47 ms |
| 1,000 | 0/8 | 8/8 | 1.62 ms |
| 10,000 | 0/8 | 8/8 | 19.31 ms |

Each query deliberately competes with newer partial-match distractors. Other-companion facts must
never appear. These tests demonstrate the retrieval-ordering defect; they do not estimate the
frequency of that defect in real conversations. The same tests reopen and traverse every stored
fact, including tied timestamps, and check missing queries and stale handles after clearing.

The fixed storage count cap is removed. Model searches remain bounded, while `ChatMemoryBrowser`
holds a single 40-fact page. Newer/Older navigation uses timestamp/identity cursors and resets the
viewport after explicit navigation. Pending results cannot replace a refreshed, cancelled or closed
view. Schema 2 adds an index in an atomic upgrade from version 1; no facts or original messages are
rewritten. The archive remains disk-bounded rather than literally unlimited.

## Memory write semantics

Creation and correction now have distinct storage semantics within the existing `save_memory`
contract. Omitting a reference requests creation; a canonical topic that already exists is refused,
even when its proposed value is unchanged. Replacement requires the exact current memory ID and
revision, retains the canonical topic and binds provenance to the current persisted user statement.
The refusal tells the model how to retrieve the current reference and retry. A failed write never
emits a saved-memory chip or successful acknowledgement.

Deterministic tests cover unchanged-value provenance preservation, stale/deleted/foreign references,
competing corrections, recovery deduplication and Undo. Two concurrent corrections from one revision
commit exactly once. This does not prove that a model will choose the correct fact, call the save
tool when appropriate, or avoid semantic duplicates under different new keys.

## Conversation validation and final checks

Ten frozen app tasks (eleven turns) run for both models through real tools and temporary storage.
Three cases add 97 saved facts and their original messages. Those source messages legitimately
enter the bounded recent context; their distracting effect is retained rather than removed to
improve scores. All forty cases complete without transport, template or generation errors.

| Full-rubric task passes | Earlier frozen worker | Current candidate |
| --- | ---: | ---: |
| Granite 4.2 3B | 5/10 | 4/10 |
| Ministral 3 8B | 4/10 | 4/10 |

This is one stochastic diagnostic pass, not evidence of an overall quality improvement or a new
leaderboard. The comparison worker is the archived release from the preceding integration study;
its client idle-cleanup serialization fix postdated that build. It has the previous prompts, model
profiles and memory semantics, but is not a newly rebuilt, bit-identical `8716a94` worker. No cleanup
or transport failure occurred. Artifact hashes and all delivered requests are retained.

Granite's additional failed task asks for saved URLs; it makes no search call. Its birthday refusal
fails in both arms despite the old lexical check counting the baseline's incidental “June 18” as a
pass. Both failures begin with zero cached tokens. Five separately registered first-turn controls
per model compare the same candidate request through native/raw generation at temperature zero.
All ten pairs have identical text, semantic tool calls and processed-token counts. This includes
the missing-search failures: no native-session integration discrepancy was found in those controls.
They do not rescore the original stochastic tasks or establish quality equivalence in all situations.

Granite correctly completes the large-store correction in both arms. The current version rejects
its first reference-free overwrite, then the model searches again and submits the correct ID and
revision. Its actual tool continuations reuse 2,372, 2,847 and 2,986 tokens. The final answer rebuilds
when the loop's message/tool representation changes; the safety gate does not force a cache hit.
Ministral's successful Vault workflow reuses 1,387 then 1,584 tokens. Ordinary second turns also reuse
state for both models, even when those turns fail the separate persistence rubric.

Both models still decline some saved-fact questions without a read tool and omit requested lasting
preference/name writes. Ministral creates an additional courier fact under a different key instead
of replacing the original in both arms: canonical-key collision checks cannot detect all semantic
aliases. It also invents book/author details in both quotation cases. Manual review marks those as
failures despite the lexical “Ivo” match. The reviewer is the implementing coding agent, not an
independent or blinded human assessor. All 44 turns have hash-bound full-rubric judgments.

The product changes are the two profile opt-ins and the deterministic retrieval/storage/UI fixes.
Automatic memory preloading remains disabled. No prompt tuning, answer-specific filter or automatic
rescore was added. Native work stopped after 692.6 of the registered 1,200 seconds once the controls
were complete; this was not a long-running soak.

Final repository checks and the [auditable evidence bundle](data/cache-memory-2026-11-04/README.md)
are recorded below.

`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make check BUILD_DIR=/tmp/sillies-cache-memory-check`
passes: 722 Swift tests with completion receipts, 94 Python tests, architecture/format checks,
925 localized source strings, fixture validation, packaged text/TTS self-checks, parent-exit controls
and catalog validation. Tests are headless; visible window/stacking checks were not run. The final
10,000-fact run also retrieves 8/8 targets, with a slowest query of 17.15 ms; the table above preserves
the first targeted run instead of choosing the faster repeat. No app restart, commit or push was made.
