# Add a local search model

Search models encode text into vectors. They help a companion find saved memories and Vault passages by meaning;
they do not generate replies, create memories or change the selected chat model.

Sillies uses Apple Natural Language assets by default. Multilingual E5 Small is an optional download
in **Settings → Search & Memory**. Keyword search remains available during preparation, unsupported
languages, cancellation and inference contention. All text and vectors stay on the Mac.

## Boundaries

| Owner | Responsibility |
| --- | --- |
| `SilliesCore` | Embedding input, vector-space identity, validated vectors and ranking composition |
| `SilliesModelStore` | Pinned artifacts, verification, resumable downloads and installation leases |
| `SilliesSearchModels` | Bounded helper transport, inference admission, cancellation and residency |
| `SilliesSearchInference` | Native model and tokenizer adapters; this process alone imports their SDKs |
| `SilliesPersistence` | Derived SQLite index, transactional invalidation and bounded result hydration |
| `SilliesVault` | Index scheduling, deadline, keyword fallback and repository integration |
| App composition | Selection, preferences, lifecycle and Settings presentation |

## Another checkpoint

Add its descriptor and immutable artifacts to
`Sources/SilliesModelStore/Resources/search-models.json`. Include publisher URL, license,
language description, memory requirement, exact revision, byte counts and SHA-256 hashes.
Existing download and selection controls discover catalog entries automatically. Translate bundled
display fields in every shipped language and regenerate third-party notices.

Use an existing provider only when its tokenizer, pooling and normalization contracts match.
A different runtime implements `PreparedEmbeddingModel` in the isolated helper and registers in
`EmbeddingRuntimeFactory`. Do not import tensor SDKs into the app, Vault or persistence targets.
No Python runtime or new third-party package is required for E5: its native adapter uses the
already-pinned official MLX libraries and Hugging Face tokenizer.

The model's identity must include the exact checkpoint and embedding algorithm version. A returned
vector also identifies its language/model space. Never compare incompatible spaces or silently
truncate a saved fact. E5 requires `query: ` / `passage: ` prefixes, attention-mask mean pooling and
L2 normalization; it must not apply an additional layer normalization.
See the [publisher's contract](https://huggingface.co/intfloat/multilingual-e5-small).

Character limits are not tokenizer limits. `EmbeddingPreparation` asks the provider whether each
window fits, splits oversized input at character-safe boundaries, and combines unnormalized means
weighted by actual token counts before normalizing once. Every character remains represented;
unsupported fragments reject the complete embedding rather than returning a successful prefix.
Cancellation, byte bounds and a finite attempt budget apply to the entire operation. An exhausted
capacity budget leaves that input available to keyword search instead of stopping index preparation.

Apple checks its native sequence capacity; E5 checks the real tokenized input including the required
purpose prefix and special tokens. A new adapter implements this capacity decision rather than
inventing a shared characters-per-token estimate. Keep the preparation revision in both provider and
vector-space identities so cached vectors rebuild when the embedding algorithm changes. Canonical
passage IDs and source locations stay stable. Settings distinguish prepared passages from passages
that actually have searchable vectors; completed indexing does not imply complete language coverage.

Apple's contextual models have distinct spaces for different script groups. Available assets and
revisions form the index identity; missing assets fall back to keywords. Sillies does not automatically
download Apple language assets. Apple's [Natural Language documentation](https://developer.apple.com/documentation/naturallanguage/nlcontextualembedding)
describes their availability and limitations.

## Persistence and lifetime requirements

Embeddings are disposable derived data in `conversations.sqlite`, separate from saved memories.
SQLite triggers remove vectors in the same transaction as any memory update or deletion, including
Undo and conversation clearing. In-flight writes must compare the current memory revision before
publishing. Unsupported facts receive an explicit processed marker so they do not loop forever.
Switching providers prunes incompatible vectors and schedules bounded background batches.

Interactive reasoning blocks background indexing for every backend, including Apple, while allowing
explicit memory-tool queries. Speech and synthesis can preempt the native worker. Cancel and reap it
before releasing admission. Pause, exclusions, termination, model removal and memory pressure stop
the owner; normal activity resumes from persisted progress. An evicted helper warms in the background
on a later lookup. Do not add an independent helper idle timer.

Semantic lookup has a 150 ms deadline, including embedding and database work. If it expires, discard
partial semantic results and use keywords. The current exact vector scan streams rows and retains
only the requested identities; it does not load every memory body. The SQLite index includes
companion, provider and embedding-space scope; writes obtain the owner from the validated memory,
never a model argument. Native vector bytes remain borrowed only inside the SQLite row callback.
Exact ranking checks dimensions, finite norms and stable identity tie-breaking. Very large indexes
may use the keyword fallback. Do not turn an arbitrary nearest neighbor into proof of a personal fact.

## Validate a provider

Run the persistence and lifecycle tests, architecture checks and `make check` (headless). Cover
correction, Undo, deletion, restart, provider changes, stale completions, cancellation, unsupported
languages, corrupted vectors and inference priority. Keep UI tests in light and dark appearance.

`MemorySearchBenchmark` exercises the real repository and native helper with a fresh temporary
database. It accepts synthetic documents and queries; expected identities stay in an external scorer.
Compare keyword-only, Apple and downloaded models using the same frozen inputs. Report positive
recall separately from negative-query candidates and check end-to-end answer grounding before
claiming improved conversational accuracy.

For fast scale checks, build `SilliesPersistenceTests` in release with `-Xswiftc -enable-testing`
and run `bash scripts/test.sh --configuration release --suite performance --bundle SilliesPersistenceTests --filter memoryVectorRankingMatchesScalarOracleAtScale`.
It compares 1K, 10K and 100K synthetic vectors against an independent scalar oracle. Setup is outside
the timer; these are database-ranking measurements, not embedding or end-to-end reply latency.
See the [scale measurements](../reports/cache-memory-followup-2026-11-04.md).

`ChatModelBenchmark` also accepts an optional `memorySearch` plan configuration with `provider`,
`identity`, an absolute `helper` path and an optional local `directory`. It creates the production
index inside each temporary fixture, waits for bounded preparation, then uses the normal memory
tool. Omitting it preserves keyword-only controls. Freeze this configuration and its artifact
hashes with the evaluator; it must never contain expected answers. See the
[production validation report](../reports/search-memory-and-prefix-profiles-2026-11-04.md).

## Vault passages

The Vault uses the same `SearchEmbeddingAccess` capability as saved memories. SQLite schema 2
adds revision-owned, overlapping passages of at most 1,200 Unicode scalars. The worker reads one
slice from the indexed document, embeds one pending passage, and yields. It never decodes the
full record body to index or rank it. The source retains the FTS row identity so advancing a long
record does not scan every document. Keyword and semantic readers remain separate from writes.

Updates invalidate passages in the record transaction; deletion cascades to vectors. A completed
embedding must still match its passage revision. Progress survives restarts, and a provider change
rebuilds incompatible vectors. Both durable producers share bounded helper admission; interactive
queries use keywords when the helper is occupied or the 150 ms deadline expires.

Vault search preserves keyword matches and fills remaining result slots with semantic candidates,
with one best passage per record. Exact URL listing keeps its literal contract. The Vault browser
shows additional candidates under **Related by meaning**. Tool output identifies semantic candidates
and keeps their full bounded passage; it must not clip a distant detail to the keyword snippet length.
Similarity is not factual confidence: an unrelated nearest neighbor can be returned. Report negative
queries separately and do not invent a universal similarity cutoff across embedding models.

`MemorySearchBenchmark` also accepts `"scope": "vault"` in its synthetic input. Expected results
remain outside the worker. Run both stores' persistence/lifecycle tests, including shared admission,
late Unicode passages, edit/delete races and version-one backfill. Index preparation uses an
indeterminate progress indicator because total passage count is discovered incrementally.
