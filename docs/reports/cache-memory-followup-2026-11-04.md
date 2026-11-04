# Memory decisions, retrieved evidence and search scale

The [cache-isolation study](cache-isolation-2026-11-04.md) qualifies bounded prefix reuse for Qwen
3.5 2B/4B and LFM 2.5 2.6B. This follow-up investigates the other three requested areas separately:
memory writes, evidence interpretation and persistent-search scaling. It does not update the public
model leaderboard or claim that prompt changes make automatic memory dependable for every model.

## Memory-save contract: rejected

The existing prompt restricts which facts may be saved but does not explicitly require a write for
every eligible fact. One candidate replaced that permissive wording with a direct requirement to
save lasting facts and ongoing preferences before answering, including beside a general question.
Correction references, provenance validation, opt-outs, secrets and quotation restrictions remained
unchanged. No second inference call, output filter or storage-validation bypass was added.

The [registered screen](../../Benchmarks/Chat/experiments/memory-contract-2026-11-04/study.json)
uses six existing development scenarios, four models and counterbalanced baseline/candidate order.
MLX uses seed 11; Apple keeps system-managed sampling. All 48 scenarios / 56 turns completed.
Every reply, call and persisted state was reviewed; these judgments are by the implementing agent,
not blinded or independent. Uncertainty is not counted as success.

| Model | Whole scenarios passed, baseline → candidate | Candidate uncertainty |
| --- | ---: | ---: |
| Apple | 1/6 → 1/6 | 0 |
| Qwen 3.5 4B | 4/6 → 3/6 | 1 |
| LFM 2.5 24B A2B | 3/6 → 2/6 | 0 |
| Gemma 4 26B A4B | 5/6 → 4/6 | 0 |

Qwen saved the corrected name in the candidate's second turn but still missed the first write.
The complete two-turn task therefore fails in both arms. All models still missed the concise-answer
preference beside the tides question. The recorded MLX requests contain the complete latest message,
new instructions and save tool; the first fact was not truncated or removed by context preparation.
Apple requests and tool traces were inspected separately because its native generations are opaque.

LFM and Gemma candidates attempted to save a previously retrieved birthday while answering a
question. The storage boundary refused the duplicate topic, preserving its original source; that
protection does not make an unnecessary write attempt correct. Apple's invented replacement IDs
were also rejected. Neither failure is attributed to missing tools or lost inputs.

Qwen correctly identified Ivo as the quoted speaker without adopting that name as the human's.
That semantic judgment passes while the missing `narrator`/`character` lexical anchor remains failed.
Its candidate porcelain answer adds an unverified terminology claim; that answer is uncertain and
needs independent review, rather than being reported as a confirmed factual error or a pass.

No candidate passed the development gate, so the conditional second seed and validation/control
phases were not run. The experiment stopped after **285.64 native seconds** of its 1,200-second cap.
The memory-prompt changes were reverted. This is a rejected candidate, not a model capability ceiling.
[Evidence, reviews, frozen-source metadata and eight recomputation audits](data/memory-contract-2026-11-04/)
remain available, including all failures.

## Vault evidence contract

`search_vault` previously included the total number of records in the entire Vault alongside the
matching results. Earlier Qwen and LFM answers treated that unrelated total as the number of saved
links. The tool now returns only query/category scope, matching records, their returned count and
explicitly bounded coverage. Record counts are distinguished from individual URLs. Empty searches
still report completion and do not invite reading a nonexistent record. The extra whole-Vault page
read is removed. The original global instruction remains useful for archived results that still
contain the old field.

The [registered comparison](../../Benchmarks/Chat/experiments/evidence-contract-2026-11-04/study.json)
planned eight frozen cases in Apple, Qwen 9B, LFM 24B and Gemma 26B, with two MLX seeds and both arms.
Its original candidate also removed the old count explanation from the global prompt. The memory-save
prompt remained the original one. All answers, calls and persisted state were reviewed.

| Model | Reviewed passes, baseline → original candidate | Candidate limits |
| --- | ---: | --- |
| Apple | 6/16 → 4/16 | Repeated companion/human-name confusion |
| Qwen 3.5 9B | 10/16 → 9/16 | One additional uncertain wording judgment |
| LFM 2.5 24B A2B | 13/16 → 12/16 | Tool-loop finalization still fails in some cases |
| Gemma 4 26B A4B | 14/16 → 12/16 | One interrupted case and two unrun; not comparable totals |

For Gemma's thirteen matched completed tasks, both arms pass twelve. Across the study, 125 of 128
planned scenarios reached a model outcome, one was interrupted by the study supervisor, and two
were not started. The interrupted artifact's generic operator-interruption message does not mean a
model failure or a user-requested cancellation. The original records remain unchanged.

This candidate did **not** establish an overall quality improvement. Apple answered the human name
Celeste instead of Pogo in both candidate repetitions. Comparing its actual first requests shows that
messages, tools and budgets agree; the only content change is the deleted global instruction, before
any Vault result is returned. That unnecessary global-prompt edit was rolled back. The final patch
changes only the Vault result contract and removes the extra database read. It adds no name filter,
model-specific prompt padding or output repair, and preserves guidance for old archived tool results.

LFM's failed traces contain four executed tool calls, then further native tool requests during the
bounded finalization attempts. Search results and empty-result status reached the model; the app did
not lose the original URL. Finalization remains an integration/model-behavior issue to investigate,
not proof that the checkpoint cannot answer the question. Qwen sometimes claims it searched without
calling a tool, or invents a nonexistent meeting. All such failures stay in the review.

An independent check verifies all **107 actual search results**: returned counts agree with the
records, status agrees with emptiness, IDs and URLs belong to the synthetic source, and original
candidate results omit the whole-Vault count. Deterministic final-code tests additionally cover
mixed record types, multiple URLs in one record, no body loads for listings, and empty searches.

The study stopped at **892.84 native seconds** of its 900-second cap, leaving insufficient time for
another request plus cleanup. The proposed final Apple check after the component rollback therefore
was **not run**. The final contract-only patch has engineering verification and restored baseline
instructions, but no separate native quality comparison. The table above is explicitly the original
candidate, not a score for the final patch. No higher model score or universal hallucination fix is
claimed. [Raw results, reviews, component analysis, execution accounting and sixteen audited exports](data/evidence-contract-2026-11-04/)
include the partial final run. Independent human review remains outstanding.

## Exact semantic-memory ranking

The first profile separated SQL access from vector arithmetic. At 100K rows, SQL traversal alone
cost about 169 ms after the initial allocation optimization; the full query took about 177 ms.
The expensive part was repeatedly resolving memory identities through the body table and then
visiting vectors in random identity order. Further arithmetic tuning would not address that cost.

The derived vector index now stores its validated companion owner and has an index on owner,
provider and embedding space. Matching vectors can be read in insertion order without a body-table
join or a whole-result sort. SQLite blobs are borrowed during each row callback. The query is prepared
once as fixed-width Swift vectors; only the best identities are retained, with explicit lexical
identity ordering for ties. No approximate-neighbor heuristic, arbitrary recent-memory cutoff or new
native dependency was introduced. Only the bounded final records are decoded.

| Synthetic saved memories, 384 dimensions | Previous median query | New median query |
| --- | ---: | ---: |
| 1,000 | 1.08 ms | 0.34 ms |
| 10,000 | 21.41 ms | 5.81 ms |
| 100,000 | 344.38 ms | 54.49 ms |

These are three-query medians in release builds on one 48 GB M4 Pro, with no model inference or build
running concurrently. Fixtures are freshly written and filesystem-cached; the final diagnostic also
scans the rows before ranking. They are not cold-disk results or latency guarantees for other Macs.
The independent scalar oracle computes the same top four identities at every size. Fixture setup,
embedding generation and model answers are outside the timer. The 150 ms semantic deadline still
includes query embedding and database work; a slow or cancelled query discards partial results and
falls back to keywords. Exact scan cost still grows with the number of matching vectors.

Schema 4 migrates existing vectors in one transaction and refuses orphaned entries without losing
the prior index. Tests cover restart, correction, Undo, deletion, stale completion, owner/space
isolation, zero and nonfinite norms, malformed byte counts, unaligned vectors, scalar tails, stable
ties and migration rollback. The migration test initially reused a handle invalidated by Forget;
it was corrected to use the returned generation, preserving the production invalidation contract.


## Final application checks

`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make check BUILD_DIR=/tmp/sillies-cache-memory-final-check`
passes with **747 selected native tests across 19 verified runs**, plus formatter, tooling tests,
architecture boundaries, localization, synthetic benchmark fixtures, helper self-checks, parent-exit
checks and catalog validation. Tests remain headless; no personal conversations, Vault records or
running app were changed. The separate release scale check passes its independent ranking oracle,
corruption and migration checks. [Verification logs and source metadata](data/cache-memory-followup-2026-11-04/)
record the commands and completion receipts. No commit, push or app restart was performed in this round.
