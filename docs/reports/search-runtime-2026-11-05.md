# Search, conversation readiness and runtime qualification

This change extends existing Sillies modules and isolated helpers. It adds no runtime dependency,
network service, automatic benchmark job or automatic settings change.

## Product behavior

- **Vault semantic search:** the existing Apple/default or downloadable search provider now indexes
  meeting transcripts, screenshot text and Stash content as well as saved memories. Keyword results
  remain available; additional semantic candidates appear under **Related by meaning**. The Chat
  search tool carries retrieval provenance and the relevant bounded passage.
- **Durable indexing:** SQLite schema 2 stores bounded overlapping Unicode passages and vectors.
  Edits/deletes invalidate derived data transactionally; late results cannot recreate old content.
  Indexing resumes after restart and shares one admitted helper with memory indexing. Search ranking
  uses a separate cancellable reader and a 150 ms optional-work deadline.
- **Chat/Talk readiness:** typed Chat stays usable without voice or microphone setup. Talk checks the
  required capabilities before capture and offers the relevant existing Settings/permission action.
  Waiting for local inference is distinguished from generating a reply.
- **Reply details:** a small message action opens a themed popover containing the prepared context
  counts, conversation notes, returned sources and optional tool results. It does not expose hidden
  model reasoning. Local diagnostic events retain counts only.
- **Runtime qualification:** all 12 downloaded text checkpoints have machine-checked profile,
  dependency and evidence identities. New prefill experiments use the same production loop with
  one profile override. Applying a reviewed result requires an explicit local command and an exact
  checkpoint/profile/helper/hardware match; stale receipts fall back to catalog defaults.
- **Portable reports:** an explicit command exports hardware, model identities, coverage, latency and
  separate automatic/review counts. It excludes prompts, replies, tool content, paths and reviewer
  names. Nothing is uploaded.
- **Meeting overlays and closure:** “A THOUGHT” inherits the mascot's actual window level and orders
  relative to it. A confirmed closed meeting window finalizes capture and releases the attachment;
  hidden/minimized windows and unreadable metadata do not. Exact-ID existence reads are batched in
  the existing metadata helper, outside the UI process. Saved records retain their original source.
- **Participate details:** fixed language/recording controls and separate Transcript/Meeting suggestions
  panes remove nested scrolling. Switching panes retains the native transcript, selection and reading
  position, and releases hidden text's keyboard focus. Long guidance/diagnostics open on demand.

The interface reuses Sillies themes, cards, controls and recovery actions. Reply-details snapshots
were inspected in light and dark appearance; all 22 localization catalogs are updated.

## Native Vault retrieval control

[Reproducible inputs, expected IDs and raw results](data/vault-search-2026-11-05.json) contain eight
synthetic records and ten queries: eight positive queries and two negative controls. One long record
places the requested evidence beyond its opening passage. A French case exercises a second language.
The production hybrid search path ran against fresh temporary databases, not the user's Vault.

| Provider | Expected record first | Expected record in top 5 | Negative queries returning candidates | Median query |
| --- | --- | --- | --- | --- |
| Keywords | 5/8 | 7/8 | 0/2 | 0.14 ms |
| Apple + keywords | 6/8 | 8/8 | 2/2 | 12.03 ms |
| E5 + keywords | 6/8 | 8/8 | 2/2 | 4.10 ms |

These are warm post-index queries on one M4 Pro, 48 GiB, macOS 26.7.2. The orchestration worker is a
debug build; the inference helper is the existing release build. Index/model preparation is excluded
from query latency. Keyword order is retained, so this is not a standalone embedding ranking.
The negative controls demonstrate why similarity cannot be presented as verified evidence. No
provider-specific confidence threshold was invented from these ten queries.
Providers can decline passages beyond their tokenizer/native sequence limit; those passages remain
available through keyword search. These cases do not establish recall across every supported language.

## Bounded prefill experiment

One candidate was registered before inference: Qwen 3.5 4B, catalog batching versus 1024-token batches.
Six existing production-tool scenarios cover identity, memory creation/opt-out, Vault links/meetings
and mixed private/general knowledge. Two repeats give 12 cases and 14 turns per arm. Each arm has a
120-second batch budget; turn/case/startup deadlines are 30/60/30 seconds. Both arms completed.

| Configuration | Automatic cases passing | Full-rubric cases passing | Median first text | Median full turn |
| --- | --- | --- | --- | --- |
| Catalog default | 8/12 | 8/12 | 2.56 s | 2.94 s |
| 1024-token batches | 8/12 | 7/12 | 2.20 s | 2.77 s |

The candidate improved median first text by about 14%, but one reply addressed the human as Pogo.
The automatic opt-out checks correctly passed the absence of writes; semantic review caught the
identity error. Qualification rejects this candidate. **No prefill override was installed or enabled.**

The memory-creation and mixed-knowledge misses existed in both arms. Inspection confirmed that the
original messages, source roles and all five tools reached generation; the failed turns emitted no
calls, so there was no rejected tool invocation or failed persistence operation to blame. Both arms
retrieved the expected documents in the dedicated Vault scenarios. This localizes the observed misses
to generation/tool selection but does not establish an irreducible model limitation.

All 28 turns received evidence-bound reviews of responses, delivered requests, calls/results and
persisted memory state. Reviews were performed by the coding agent, not an independent human reviewer.
A single Mac, two repeats and baseline-first ordering cannot establish causal quality loss or broad
hardware superiority. Normal background applications were not controlled. This is a conservative
screening result, not a replacement for the published model leaderboard.

Raw audited evidence:

- [Catalog-default control](data/search-runtime-prefill-control-2026-11-05.json.gz)
- [1024-token candidate](data/search-runtime-prefill-candidate-2026-11-05.json.gz)

The evidence auditor reproduced both archives. The portable export was exercised against the real
control run and inspected for excluded content. Qualification tests reject changed conditions,
incomplete or uncertain reviews, new failures and invalid timings rather than reporting them as gains.

## Validation

The focused checks cover passage migration/Unicode bounds, stale edits/deletes, shared helper
admission/cancellation, readiness recovery and mode changes, reply persistence/rendering, stale
calibration identities, malformed metadata and meeting capture finalization. Headless native checks
verify exact-ID lookup and window destruction. Participate checks cover minimum size, long suggestions,
errors, language switching, selection/scroll preservation, keyboard focus and unread state after closure.
Light/dark and failure-state snapshots were inspected.

- `make check`: passed, with verified completion of 817 Swift tests across 20 runs and 112 Python tests;
  architecture/package rules, 22 localization catalogs, native inference self-checks and helper shutdown
  checks also passed.
- `make stress`: passed, with verified completion of 210 tests across 13 runs.
- `make race-check`: passed, with verified completion of 258 tests across 16 runs and no reported races.

Visible app/window-stacking and real Zoom/Teams capture checks are separate opt-in workflows; they
were not run in this session. The user's running app was not restarted. The validation build is at
`/tmp/sillies-search-runtime-check/Sillies.app`; local layout previews and command logs are under
`build/search-runtime-2026-11-05/`.
