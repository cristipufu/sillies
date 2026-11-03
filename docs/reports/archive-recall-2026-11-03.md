# Archive recall: relevant evidence and verified limits

Archive search now returns the matching passage of a message instead of its first 600 characters.
This fixes a reproduced application defect across Apple, LFM 2.5 24B and Gemma 4 12B. It does **not**
make automatic recall perfect: Gemma 12B still skips two implicit lookups in the long-history control.

## What changed

- FTS5 ranks message identities before extracting relevant snippets for the bounded result set.
  Original messages remain intact. Search stays on its cancellable read-only connection, separate
  from saves, paging and checkpoints.
- Results identify their conversation source, original speaker, message sequence and ISO date.
  They distinguish partial excerpts, additional matches, no matches and a query requiring keywords.
  Selection uses relevance; presentation uses chronology so corrections have an explicit order.
- Smaller model evidence budgets receive fewer complete result objects. JSON and quotations are
  never arbitrarily cut. An unusually large indexed word can exceed the escaped-JSON excerpt limit;
  that result retains its identity and explicitly reports omitted text instead of inventing evidence
  or claiming the search missed.
- Instructions separate earlier chat, personal memories, saved Vault records and general knowledge.
  They explicitly distinguish retrieving an old statement from saving a new personal assertion.
  No intent classifier, forced search, additional model call, answer filter or model-specific prompt
  was added. There are still five tools.

The excerpt uses SQLite's [documented FTS5 snippet function](https://www.sqlite.org/fts5.html#the_snippet_function).
This remains keyword retrieval, not semantic search. A snippet is incomplete evidence, and a limited
set of matches cannot prove that a fact is absent from the whole archive.

## Controlled native runs

Baseline: committed `a83ee8383d053b1e4f69827b8f34cd3fe61282d5`. Release workers and helper bundles were
frozen before inference. The comparison uses one M4 Pro with 48 GiB RAM, macOS 26.7.2 build 25G332.
Existing installed models were reused; no user conversation or Vault was opened.

Five frozen scenarios contain nine turns per model: the previous 192-message continuity case,
a detail buried in a long message, an implicit recall paraphrase, a genuine miss, and interleaved
chat/Vault/general questions. Each turn has a 60-second deadline; batches are resumable and bounded.
The corpus was frozen before baseline inference. The same cases, model revisions, helper, model
profiles and evaluator were used before and after the change. The comparison does not run background
checkpoint maintenance; it isolates foreground archive retrieval and source choice.

| Model | Three continuity facts, before → after | Buried detail, before → after | Complete scenario checks, before → after |
| --- | --- | --- | --- |
| Gemma 4 12B | 1/3 → 1/3 | Missing → correct | 2/5 → 3/5 |
| LFM 2.5 24B | 3/3 → 3/3 | Missing → correct | 2/5 → 4/5 |
| Apple | 3/3 → 3/3 | Missing → correct | 2/5 → 2/5 |

The continuity-fact column assesses factual content. Apple still fails all three exact-format
checks because it answers in sentences instead of returning just the requested code or name.
The complete-scenario column also requires correct tool behavior; a correct final sentence alone
does not pass it. These are diagnostic controls, **not new leaderboard scores**.

The implementing agent reviewed all 62 observed turns across the comparison and two diagnostic
runs, binding judgments to response and task-evidence hashes. This is not independent human review.
It is one observation per case/configuration, with stochastic generation and no matched sampling
seed; it does not establish reliability rates or a statistically significant speed improvement.

### Separating retrieval from tool selection

With the original prompts and only the retrieval changes, Gemma found the buried detail correctly.
It still skipped the older release-code and checklist-owner lookups. The revised instructions also
left these two failures unchanged. Captured requests included the tools and recent-window notice;
the model completed with plain text and no call, so there was no missing search result to deliver.
The separate implicit paraphrase and mixed-source cases did invoke conversation search successfully.

A diagnostic enabled Gemma's native thinking template and reserved 512 conversation reasoning tokens,
following Google's [thinking-mode interface](https://ai.google.dev/gemma/docs/capabilities/thinking).
It still missed the first implicit lookup; a later lookup exceeded the turn deadline. The explicit
long-message lookup succeeded. This temporary helper/profile experiment is **not shipped**. The
normal helper source, model files and model defaults are unchanged.

The model receives native tool schemas and call/result messages, following
[Gemma's function-calling protocol](https://ai.google.dev/gemma/docs/capabilities/text/function-calling-gemma4).
The results establish a reproduced limitation under these tested inputs and settings, not that the
model cannot use tools or that a different verified configuration could never improve recall.

### Other observed behavior

- LFM's long-message lookup used one search instead of three; the observed turn took 16.02 seconds
  instead of 24.82. Its mixed question also stopped creating an inappropriate saved memory in this
  pass. The missing-evidence case completed instead of ending in `invalidResponse`, but still searched
  the Vault despite the question specifying earlier chat, so it remains a failed scenario.
- Gemma's mixed question used one conversation search instead of three private searches. It still
  expanded the missing-evidence query into the Vault, violating the frozen source-scope constraint.
- Apple retrieved the buried fact, but attempted a memory correction using an archive message ID.
  Existing correction validation refused it; nothing was saved. It also unnecessarily searched
  personal memories for the standalone general-knowledge question. Both failures remain recorded.

These observations support retaining the retrieval correction and clearer source contracts. They
do not support claiming flawless recall, memory decisions, source selection or model independence.

## Engineering validation

`make check` passed with 695 native tests across 18 checked runs, 92 Python tests, architecture and
format checks, headless presentation checks, fixture validation, localization, helper self-tests,
helper shutdown checks and catalog validation. Builds used a separate temporary app bundle.

Five new regressions cover long-message evidence and diacritics, chronology and reduced evidence
representations, empty queries and companion/current-message scoping, attribution plus edits/deletes,
and oversized excerpt omission without clipped JSON or a false search miss.

The existing million-message fixture verified concurrent saves/page reads during a broad executing
search, cancellation inside SQLite, and successful reuse of the reader afterward. Observed save+page
time was **5.01 ms**, cancellation **7.77 ms**. These are single-run measurements, not constant-time
search guarantees. Broad ranking can still take time; it does not occupy the writer or main actor.

After native runs, the oversized-excerpt bound was added and covered by the final regression suite.
No excerpt in the recorded native runs exceeds that bound. The source receipt explicitly records
this difference rather than labeling the earlier native binary as the final build.

## Evidence and reproduction

- [Baseline evidence](data/archive-recall-2026-11-03/baseline.json.gz) and [audit](data/archive-recall-2026-11-03/baseline-audit/audit.json).
- [Retrieval-only control](data/archive-recall-2026-11-03/retrieval-only.json.gz) and [audit](data/archive-recall-2026-11-03/retrieval-only-audit/audit.json).
- [Revised integration](data/archive-recall-2026-11-03/final.json.gz) and [audit](data/archive-recall-2026-11-03/final-audit/audit.json).
- [Thinking diagnostic](data/archive-recall-2026-11-03/thinking.json.gz), [audit](data/archive-recall-2026-11-03/thinking-audit/audit.json) and [temporary configuration](data/archive-recall-2026-11-03/thinking-control.json).
- [Frozen corpus](data/archive-recall-2026-11-03/corpus.json.gz), [source verification](data/archive-recall-2026-11-03/source-verification.json) and [validation receipt](data/archive-recall-2026-11-03/validation.json).

Each compressed run includes its full synthetic corpus, native requests, tool results, persisted
memory state, failures, reviews and binary/resource hashes. Private reasoning text is excluded.
Extract the corpus into a directory and use the [bounded runner](../../Benchmarks/Chat/README.md)
with `--corpus` pointing there. Keep new binaries or policy changes in a new output directory.
Do not merge these diagnostics into the published full comparison or retry failures into a score.
