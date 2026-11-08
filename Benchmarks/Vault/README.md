# Vault qualification

These probes exercise the real local persistence, embedding helper and search paths with disposable
data. They do not open the person's Vault. Work is resumable across process exits; routine tests stay
headless. Results describe a specific corpus, provider revision and machine, not an unlimited scale guarantee.

## Retrieval quality

The frozen corpus combines the **5,183-document / 300-query BEIR SciFact test split** with 15 authored
everyday documents and 35 queries. The additional cases cover multilingual and cross-language retrieval,
tag filters, a filter with no documents, and absent information. Trashed documents are distractors and
must not leak into active results. This is mostly a scientific-abstract corpus; the small everyday set
is a regression fixture, not a representative survey of personal libraries.

For the expanded suite, add `--additional Benchmarks/Vault/multilingual.json` to the preparation
command. This preserves the frozen baseline and adds **49 documents / 98 queries**: native phrasing,
paraphrases and English cross-language questions across all 22 app languages; nearby distractors;
missing private details; late evidence in long notes; and active/Trash/tag isolation. The combined
corpus has **5,247 documents / 433 queries**. These authored cases have not had independent
native-speaker adjudication and must not be presented as an unbiased language leaderboard.

1. Download the [BEIR SciFact archive](https://public.ukp.informatik.tu-darmstadt.de/thakur/BEIR/datasets/scifact.zip).
2. Prepare it with `python3 Benchmarks/Vault/prepare_scifact.py /path/to/scifact.zip /new/output/corpus`.
   The preparer verifies the pinned archive checksum and writes separate input, expected-label and manifest files.
3. Build `swift build -c release --product MemorySearchBenchmark` and build the app's search helper.
4. Run `run_retrieval.py` with `--stage seed`, then `--stage index`, then `--stage query`.
   Each invocation accepts at most ten 20-second slices; each child process has a 90-second watchdog.
   Repeat a stage until its output says `complete: true`.
5. Score the completed JSONL with `python3 Benchmarks/Vault/scoring.py inputs.json expected.json results-e5.jsonl`.

Example (use the actual paths from your build and installed model):

```sh
python3 Benchmarks/Vault/run_retrieval.py \
  /path/to/MemorySearchBenchmark /new/output/corpus/inputs.json \
  /new/output/e5 /path/to/SilliesSearchInference \
  e5 pinned-model-identity --model /path/to/model --stage seed --slices 1
```

For the native provider use `apple apple-contextual` without `--model`. The helper derives the actual
Apple asset identity. Provider changes require a separate run directory. A receipt pins the input and
both executable checksums; a changed build must use a new run directory. Model paths/revisions are also
recorded; retain a model-file checksum manifest with published results. A prepared disposable database
can be cloned to a new run directory to reuse its canonical vectors after a tooling-only change.

### What is measured

| Output | Meaning |
| --- | --- |
| `keywords` | The workspace's production Best match page, first five records |
| `semantic` | Production related search, first five records; canonical filtering remains active |
| `fused` | A diagnostic application of the existing rank-fusion policy to the two top-20 lists; not the workspace's visual list order or a full assistant benchmark |
| `exactSemantic` | Same provider and persisted vectors, scored without approximate candidates; isolates index misses from model relevance |
| Availability | Includes unavailable, timeout and failure results; failed queries remain in the denominator |
| `exactAvailability` | Explicit oracle outcome, including unsupported input; a completed refusal counts as a miss |
| `relatedButInsufficient` | Annotated nearby documents that lack the requested fact; reported separately from support |

The scorer validates query completeness, duplicate/unknown IDs, filter eligibility, relevance grades,
rank limits and elapsed times. Hit@5, recall@5, precision@5, MRR@5 and nDCG@5 have independent arithmetic
tests. Absent queries are reported separately: returning related suggestions is not proof that the
requested fact exists. No relevance threshold is fitted to this set. Exact-top-five overlap measures
index fidelity, not relevance. Apple can decline unsupported language/input combinations; those must
remain visible in availability counts.
If any query requests the exact oracle, every query must have a completed oracle result and valid
elapsed time. A missing oracle result cannot silently reduce the comparison denominator. An empty
filtered result remains valid and is counted as a query, with no top-five overlap denominator.
Authored supporting quotes must exist verbatim in their labeled source. This checks provenance, not
semantic entailment. Related-but-insufficient labels must be eligible and disjoint from supporting
IDs. None of these annotations enter worker inputs. Returning a related document on an absent-detail
query is not an answer hallucination: this benchmark performs retrieval and does not generate answers.

The manifest reports inputs exceeding the production semantic query limit of 200 characters. The
keyword path keeps its existing query contract. Do not silently alter either input to inflate scores.
SciFact labels are independent expert annotations. The authored cases are intentionally small and
should be extended with held-out, independently reviewed tasks before choosing a universal default.

### Dataset attribution

SciFact: Wadden et al., *Fact or Fiction: Verifying Scientific Claims*, EMNLP 2020.
See the [original dataset](https://github.com/allenai/scifact) and
[BEIR](https://github.com/beir-cellar/beir). Claims and evidence labels are CC BY 4.0; abstracts are
ODC-By 1.0, as described in the [dataset license](https://github.com/allenai/scifact/blob/master/LICENSE.md).
Downloaded documents are not committed here. The preparer and authored cases are part of Sillies.

## Storage lifecycle and scale

`VaultScaleBenchmark <mode> <disposable-directory> <target-count> <slice-seconds>` supports:

| Mode | Purpose |
| --- | --- |
| `seed` | Short synthetic records, up to one million, through normal commits |
| `seed-random` | The same content with normal random record IDs; checks that a ranking optimization does not depend on fixture insertion order |
| `seed-meetings` | Long, 300-turn synthetic transcripts plus a 64 KiB attachment each; storage fixtures, not playable recordings |
| `query`, `concurrency`, `long-document` | Exact paging/ranking, concurrent reads/edits/cancellation, bounded document editing |
| `backup`, `restore` | Complete native backup and next-launch restore, record counts, every attachment and sampled full section content |
| `verify-restore` | Resume verification of an already installed disposable restore without copying it again |
| `retention`, `clear` | Request durable cleanup once on a disposable copy |
| `drain` | Resume cleanup for one bounded slice, checking page-read latency and completion |

Seed/drain slices accept at most 30 seconds. Query/backup/restore cover complete operations: wrap them
in an external watchdog and retain failures, rather than counting a timed-out partial result. Never
reissue clear/retention between drain slices. Check SQLite integrity, remaining physical rows, search
entries and attachment files after completion; an empty visible page alone is insufficient evidence.

To qualify interrupted indexing, terminate a **disposable probe and its owned helper**, restart it and
check canonical vector counts and completed native checkpoints. Never terminate the running app's helper.
Check cancellation/deletion/provider-switch tests alongside real embeddings; index throughput alone
does not establish lifecycle correctness.

### Fixture retention

A million-record SQLite fixture can occupy about 8 GiB. Separate retention, clear, backup and restore
experiments can accumulate many copies; APFS clones still grow as those copies are modified. Treat
these databases and native vector indexes as disposable working data, not as the evidence archive.

When a comparison finishes, retain its generator revision, input/checksum manifests, raw query results,
scores, completion receipts and report. Then remove its generated databases, indexes, backup directories
and restored copies after confirming that no probe uses them. Preserve frozen inputs and results kept
beside a database. Recreate fixtures for later experiments with the commands above rather than keeping
every historical working copy. Keep only the current app bundle and one rollback build.

Measure both workspace usage and available disk space before and after cleanup: shared APFS blocks
mean the sum of directory sizes is not the amount of physical space reclaimed. Never include the
person's Application Support Vault or installed model stores in a build-artifact cleanup.

## Native interaction

`VaultNativeInteractionTests` exercises real search-field focus, editing, reopening, resizing and
scrolling. Native stacking and clipboard-responder checks live in their existing shared suites.
Run explicitly on an **unlocked** desktop:

```sh
bash scripts/test.sh --presentation gui --filter 'vaultNative|foregroundContentOccludesNormalMascots|commandCCopies'
```

Set `SILLIES_VAULT_NATIVE_TIMING` to an output JSON path to retain per-frame operation and display-link
interval samples. These include AppKit layout, not GPU presentation timestamps. Do not substitute them
for a visual smoothness assessment or count lock-screen runs as native activation evidence.
