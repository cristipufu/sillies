# Local Chat evaluation

Can a small local model be a useful companion **and** a dependable agent? This suite tests the
configuration Sillies actually ships: its conversation service, prompts, native message roles,
tool adapters, persistent memories, Vault retrieval and context compaction.

It runs without windows, recording, access to your Vault, or changes to your app settings.
All records, people and saved memories are synthetic. Native Swift workers run the model;
a Python 3.11+ standard-library supervisor manages deadlines, receipts and scoring.
There is no Python inference runtime, cloud judge or additional dependency.

Production semantic-memory comparisons can inject a `memorySearch` configuration into the worker
plan. Each case builds its own persistent index and uses the normal memory tool; the configuration
and artifact hashes must be frozen with the run. See [Search & Memory validation](../../docs/reports/search-memory-and-prefix-profiles-2026-11-04.md)
and the [provider contract](../../docs/contributing/search-models.md).

Read the [model selection summary](../../docs/local-text-models.md#which-model-should-i-use)
and the [reviewed thirteen-model comparison](../../docs/reports/corrected-local-chat-models-2026-11-02.md).
Both LFMs also have a [complete rerun after integration fixes](../../docs/reports/lfm-chat-rerun-2026-11-02.md),
with fresh reviews, before/after measurements and diagnostic controls. Its single pass is separate
from the older comparison; it does not establish repeatability or update the other eleven models.
The [earlier seven-model comparison](../../docs/reports/local-chat-models-2026-11-02.md) preserves
its separate repeat measurements; those repeats do not certify the newer integration.
The [first comparison](../../docs/reports/local-chat-models-2026-11-01.md) and its
[audit](../../docs/reports/chat-benchmark-audit-2026-11-02.md) remain available as historical evidence.
The original checks had false positives and did not prove summary retention.

`fixtures` validates every seeded database without loading a model and runs in `make check`.
Screenshot fixtures include real tiny PNG attachments and synthetic OCR text, so the normal
screenshot category can retrieve them. This measures text-based screenshot retrieval, not vision.
Each inference case also runs the same preflight before admitting the model.

Memory fixtures create provenance messages as well as stored facts. For retrieval experiments, place
those messages outside the recent-history window and add `initial_context_omits` with the source
statements. This checks instructions and messages **before** any retrieval call; later tool evidence
is allowed. A failed fixture check invalidates the comparison and cannot receive a manual rubric pass.
The separate `retained_context_omits` check deliberately examines recent messages only, so a summary
can carry the answer when testing compaction.

## What it covers

The corpus has **74 scenarios, 93 tool-profile cases and 134 turns per model**. The primary five-tool
comparison contains all 74 scenarios and 107 turns. On November 2 the
context fixtures were corrected: both the original fact and its correction now precede the
compaction boundary, and scored turns check that the target fact is absent from recent raw messages.
These corrected cases are a new corpus revision, not comparable rescoring of the original run.

| Group | What can go wrong |
| --- | --- |
| General knowledge | Searches private records for ordinary facts, gives incorrect answers |
| Vault | Invents saved URLs, chooses the wrong screenshot or meeting, loses source attribution |
| Mixed knowledge | Confuses world knowledge with private facts, loses earlier results after a topic change |
| Identity | Uses the human's name as its own, repeats an earlier mistaken identity |
| Memories | Claims a save without writing, forgets corrections, saves hypothetical or third-party facts |
| Context | Loses corrected facts after compaction or cannot continue a long conversation |
| Evidence | Follows instructions embedded in a saved record, claims a screenshot is a live screen |
| Languages | Cannot answer ordinary questions in the requested language |
| Tool scaling | Becomes less reliable with 0, 1, 3, 5, 8 or 12 available tools |

Five tools match the app: `search_vault`, `read_vault_record`, `search_conversation`,
`search_memories`, `save_memory`. Larger profiles add harmless synthetic distractors; they never
read your calendar, contacts, clipboard or files. Smaller profiles deliberately remove capabilities.
The tool-count sweep contains four fixed scenarios, so it is an exploratory curve, not enough to
declare a universal optimal tool count. The five-tool profile is the primary comparison.

## Run a bounded batch

From the repository root:

```sh
source scripts/toolchain.sh
swift build --product ChatModelBenchmark
make debug BUILD_DIR=/tmp/sillies-eval-app
python3 Benchmarks/Chat/benchmark.py validate
python3 Benchmarks/Chat/benchmark.py fixtures
python3 Benchmarks/Chat/benchmark.py run \
  --models apple \
  --helper /tmp/sillies-eval-app/Sillies.app/Contents/Helpers/SilliesTextInference.app/Contents/MacOS/SilliesTextInference \
  --output build/chat-benchmarks/my-run --max-seconds 180
```

Repeat the same command to continue. Completed cases, **including failures**, are never silently
rerun. A batch stops admitting cases after its budget; a case already running may finish within
its separate deadline. Defaults: 60 seconds per turn, 180 per case, 90 for worker startup.
The supervisor terminates the worker process group on a deadline, even if native inference ignores
Swift cancellation. Temporary databases belong to the parent and are removed after a killed worker.
Native generation start/finish events in `worker.stderr.log` retain content-free stage metrics
when an unfinished turn is killed. They have no job identifiers or wall timestamps; preserve their
ordering and do not claim exact per-case attribution without additional evidence.
Three interrupted workers stop that model's current batch. Missing models remain visibly pending.
An operator interruption after case admission leaves an explicit receipt and is not silently retried.
Keep it separate from model failures when interpreting an interrupted run.

Downloads are explicit and use the existing verified catalog installer:

```sh
swift build --product TextModelBenchmark
.build/out/Products/Debug/TextModelBenchmark install qwen-3.5-4b /tmp/sillies-eval-models
python3 Benchmarks/Chat/benchmark.py run \
  --models apple qwen-3.5-4b --models-root /tmp/sillies-eval-models \
  --helper /tmp/sillies-eval-app/Sillies.app/Contents/Helpers/SilliesTextInference.app/Contents/MacOS/SilliesTextInference \
  --output build/chat-benchmarks/comparison --max-seconds 180
```

All catalog text models work through the same runner. Use `--tag smoke` for the short pilot,
`--groups mixed-knowledge identity` for focused investigation, and `--repeats 3` for variability.
`--order-seed` (default `0`) shuffles cases reproducibly within each repetition. Every compared model
gets the same order; changing the seed requires a new run. This reduces fixed case-order effects,
but does not control thermal conditions or cold starts. Rotate model order in separate replications.
Choose these **before** starting a run. Corpus, evaluator, binaries, model list, deadlines and
machine conditions are hashed/frozen; changed inputs require a new output folder. Machine metadata
contains OS version/build, processor family, architecture, memory and logical processor count;
it contains no hostname, serial number or user identifier. Each worker's model revision and
environment must also match the first worker before another case is admitted. Apple's model assets
remain system-managed; an unchanged OS build cannot prove that Apple has not updated those assets.
A documentation-only commit does not invalidate identical binaries. The initial source commit
remains in the run metadata.
New runs also freeze the full evaluator corpus, helper bundle resources (including Metal kernels)
and the worker's bundled catalog. The bundled inference helper is required for this resource check.
Do not run two writers against the same output directory, or rebuild/replace binaries during inference.

Use release builds when comparing interactive latency. Build into a separate folder to leave a
running app untouched, then pass the release worker explicitly:

```sh
source scripts/toolchain.sh
make build BUILD_DIR=/tmp/sillies-eval-release
chat_worker="$(swift build --configuration release --show-bin-path)/ChatModelBenchmark"
python3 -B Benchmarks/Chat/benchmark.py run \
  --worker "$chat_worker" \
  --helper /tmp/sillies-eval-release/Sillies.app/Contents/Helpers/SilliesTextInference.app/Contents/MacOS/SilliesTextInference \
  --models apple qwen-3.5-2b qwen-3.5-4b qwen-3.5-9b gemma-4-e4b ministral-3-8b gemma-4-26b-a4b \
  --models-root /tmp/sillies-eval-models \
  --output build/chat-benchmarks/release-comparison --max-seconds 180
```

Install each selected model first. Resume the same command until coverage is complete. For two
additional extension passes, retain those binaries and settings, reverse the model order, choose a
new output directory, and add `--tag heldout-2026-11-02 --repeats 2 --order-seed 104729`. Combining
those passes with the extension cases in the full comparison gives three observations per scenario.
The published report identifies its source commit; a changed app configuration is a new comparison.

## Read the results honestly

The [five-opportunity study and evaluator review](../../docs/reports/model-opportunities-2026-11-04.md)
contains the latest focused memory/cache/retrieval experiments, including invalid runs and why they
cannot support model conclusions. Its results do not replace the full-corpus comparison.

Review the measuring system before publishing a comparison. The `app` profile admits the production
tool set dynamically; restricted profiles are deliberate ablations. Inspect the actual delivered
definitions, prompt roles, tool results and stop reasons. A missing tool in the harness is an invalid
experiment, not a model failure. Freeze the evaluator, catalog, worker and helper before resumable
runs; do not change them between batches.

Fixture self-checks protect tool inclusion, private-channel redaction and memory-evidence capture.
Evaluator tests include false save acknowledgements, missing state, empty/failed replies, stale
reviews, tampered scores, missing cases and interrupted workers. Recomputing a score with the same
function checks reproducibility; it cannot independently prove that function's logic is correct.
Full-rubric review and these adversarial tests remain necessary. Neither proves a benchmark is
bug-free or replaces independent human review.

The November 2 extension adds 22 previously unrun scenarios (29 turns), tagged
`heldout-2026-11-02`. Freeze them before inference; do not tune prompts to their results and keep
calling them held out. They broaden facts, phrasing, memory opt-outs, identity, mixed questions and
full-record retrieval. They are still authored by the implementing agent, not an independent test set.

The incremental context scenario appends archived messages between measured turns while retaining
the actual previous checkpoint. Receipts record `compactionCalls`, `compactionSeconds` and timestamped
`textEmissions`; excessive summarization can fail even when the final answer is right. Call bounds
alone do not identify replay: inspect the recorded summary inputs to distinguish replay from
processing additional old turns because a summary is verbose. The first
turn includes backlog compaction; subsequent turns measure checkpoint reuse. Added history is
synthetic fixture input, never an expected answer injected through the evaluator.
The later `amber-61` correction can remain in recent context; this case does not prove that the new
correction survives another compaction. Separate corrected-code cases place both the original fact
and its correction beyond the recent-context boundary.

The November 2 release comparison includes a full pass plus two additional passes of the 22-case
extension in reversed model order. The extension was frozen before its first inference, but a
diagnostic run exposed a general Vault body-reading defect before the final comparison. It is now
regression material, not an untouched independent holdout. The primary pass has agent rubric reviews;
the additional passes report automated outcome variability separately.

A user-facing task score must state its denominator and whether it means automated checks or
full-rubric review. Keep failures, privacy violations and unresolved reviews visible. Do not average
speed, correctness and privacy into a single unexplained number. Hardware guidance uses catalog RAM
admission limits; timing measured on one Mac is not a prediction for every Mac with that much RAM.

`report.md` and `summary.json` show coverage, group/profile breakdowns, errors and latency.
Each `MODEL/cases/*.json` preserves the reply, partial output, actual executed tool calls and
arguments, stored memories, retrieved IDs, compaction attempts, app-level backend requests, token measurements and
the checks that passed or failed. `events.jsonl` also preserves progress up to a hard timeout.

New memory snapshots include the persisted identity, revision and source-message identity as well as
the fact and source quote. Older snapshots do not contain those fields; inspect their actual tool
references and write receipts, and disclose that weaker evidence. Never infer an empty store from
a missing snapshot after a process deadline.

New workers record `memoryCommitSeconds`: elapsed time from the same turn start used for text
timing until the app receives each successful memory-write receipt. Replayed receipts are counted
once. This measures acknowledgement latency, not SQLite transaction duration; a missing field in
an older receipt is unmeasured, while an empty array in a new receipt means no acknowledgement
was observed. Always inspect the persisted facts separately, including when generation fails.

The tool wrapper records executed calls; duplicate-cache hits and calls rejected before execution
are not counted as executed calls. Their resulting generation errors remain in the receipts.
Backend requests are not a full dump of each framework's internal transcript/token stream or every
tool-loop inference round. A compaction attempt alone does not prove a successful model summary;
the production fallback can use literal excerpts. Inspect the retained context and final answer.

Keep these measures separate:

- **Behavior:** whether the right tools ran, a memory really persisted, sources were returned,
  compaction occurred, and generation completed. Do not turn "I'll remember that" into a pass.
- **Exact answer:** both the content and the requested short-answer format. A correct explanation
  can fail a request to return only a name; this is not automatically a factual error.
- **Lexical anchor:** a weak diagnostic, not semantic accuracy. A reply can contain "Everest"
  while contradicting it, hallucinating extra facts or repeating itself.
- **Semantic review:** judge the raw reply against the case rubric. Store an array in
  `reviews.json` with `model`, `job`, zero-based `turn`, `responseHash`, `verdict`
  (`pass`, `fail`, `uncertain`), `evidenceHash`, `reviewer`, `scope: "rubric"` and a short `note`.
  Copy both hashes from the turn receipt. Review the entire rubric, including calls and state,
  source attribution and unsupported claims. Reporting rejects stale or duplicate reviews.
  Existing reply-only/content-only reviews remain visible separately; they are not full-rubric passes.
  Unreviewed and uncertain cases remain pending unless another reviewed turn already establishes
  failure of that task. An uncertain turn is never counted as passing. Agent review is
  preliminary and should receive independent human review before release claims.

An automated case pass is never a full-rubric pass by itself. The report shows both review coverage
and planned-case denominators. Partial runs cannot become `5/5` leaderboards by omitting unfinished
cases. New-schema reports and resumes recompute checks from the frozen corpus and reject altered,
duplicate or unrelated receipts. Evidence hashes detect inconsistent edits, not deliberate forgery.

Regenerate with `python3 Benchmarks/Chat/benchmark.py report --output PATH`.
Publish an auditable compressed snapshot with `python3 Benchmarks/Chat/benchmark.py export
--output PATH --archive docs/reports/results.json.gz`. It includes configuration, metadata,
all case receipts and any semantic reviews; keep the full worker logs locally for diagnosis.
Export recomputes the summary from receipts and reviews. Audit checks published review totals as
well as automatic primary metrics. Legacy partial review summaries are explicitly distinguished
from verified full summaries; a failed case or failed/empty turn cannot receive a full-task pass.
Do not rank models with unequal coverage, or hide failed/timeout cases from the denominator.
A failed compaction may fail a full case; subsequent turns still have explicit failure receipts.

`python3 scripts/summarize-chat-benchmarks.py PRIMARY REPEATED --output measurements.json` derives the
published comparison from complete run directories or exported `.json.gz` archives, without inference.
It verifies matched binaries, installed model revisions, runtime, hardware and
fixtures, rejects incomplete or unresolved primary reviews, and retains failed repeat outcomes.
Omit `REPEATED` for a complete single-pass comparison; its output contains no repeat measurements
and must not be presented as evidence of stability across runs. Every primary turn still needs a
full-rubric review. A demonstrated failed turn settles a task as failed even if another turn remains
uncertain; otherwise an uncertain task blocks scoring. The underlying judgments remain unchanged.
Its short-answer timing subset includes only reviewed, correct exact answers; it skips whitespace
and measures their first answer-bearing text. This conditional subset is not an all-task latency score.

For diagnostic reruns, `python3 scripts/recheck-chat-reviews.py OLD NEW MODEL` can reuse an existing judgment
only when the frozen corpus and task evidence match. It compares questions, rubrics, replies,
tool arguments/results, saved facts and provenance, source IDs, summaries, checks and compaction
counts. Timing and generated conversation message IDs are excluded; changed task evidence requires
a fresh review. Reused judgments carry their original evidence hash. Publish the source diagnostic
archive alongside them, and never describe this as independent or blinded review.

Audit the published baseline without loading models or rewriting any evidence:

```sh
python3 -B Benchmarks/Chat/benchmark.py audit \
  --archive docs/reports/data/local-chat-models-2026-11-01.json.gz \
  --corpus-snapshot docs/reports/data/local-chat-models-2026-11-01.corpus.json.gz \
  --output build/chat-benchmarks/baseline-audit
```

New archives embed their frozen corpus and do not need `--corpus-snapshot`. Audit verifies receipt
identity, questions/rubrics, hashes, checks and primary aggregate metrics. Reproducing those numbers
does not prove the checks measure the intended behavior; that requires the rubric/fixture review.

### Timing and experimental limits

Timing covers the production conversation service plus trace/persistence instrumentation. First
text is the first received nonempty delta, not UI rendering or audible speech. Successful-turn
latency percentiles exclude errors; errors are shown separately, including partial output.
The first turn after a worker starts may load weights. Later turns reuse the normal runtime;
Apple assets may already be warm. This is not a controlled cold-start benchmark. Background
work, hardware, thermal state, OS model updates and sampling affect results.

Production Apple decoding is greedy when tools are present and stochastic without tools.
The downloaded models use the production conversation sampler (temperature 0.7, top-p 0.9,
repetition penalty 1.08). Therefore Apple's zero-tool comparison also changes sampling policy.
Record this confound; do not attribute the entire difference to tool count. No fixed seed is
available uniformly across providers. Repeat promising configurations before a release decision.

This evaluates **the model + pinned runtime + app prompt/tool configuration**, not a model's
maximum possible capability. Keep the production configuration frozen during comparisons;
put prompt/runtime experiments in separate runs. One corpus, few languages and synthetic data
cannot establish universal factual accuracy, safety or quality on every Mac.

## When to run which evaluation

| Trigger | Required evidence |
| --- | --- |
| Harness, storage or protocol change | Deterministic supervisor/scorer tests, fixture preflight, archive audit; no model download required |
| Prompt, tool, model revision or runtime change | Bounded real-model cases for the affected behavior and general/private topic switching; keep a frozen control |
| Choosing a default model | Same full corpus/configuration for every candidate, at least three exploratory repeats, full rubric review and held-out tasks; report case-level variability |
| Claiming speed improvements | Separate cold/warm runs, release build, controlled background work and more than one Mac; measure substantive answer and audible speech separately |

Three repeats help reveal instability; they do not establish statistical significance or turn
repeated templates into independent questions. Predeclare tasks, rubrics, model settings, review
selection and release criteria before inference. Do not choose a pass threshold after seeing results.
Use a separate held-out set after prompt tuning; this small corpus alone is a regression suite.

## Extend it

Add a case to `cases/*.json`: unique ID, group, tool profiles, user turns, semantic rubrics and
objective checks. Optional `history`, `records`, `memories`, `owner` and `language` seed the fixture.
Expected answers and rubrics stay in the evaluator; the worker receives only whitelisted scenario
inputs. Never put gold answers in a model instruction to make the test easier.

Add a text provider through the [existing model guide](../../docs/contributing/text-models.md).
No model-specific benchmark switch or duplicate inference implementation is necessary.
Keep the Swift worker independent of AppKit and model SDKs; architecture checks enforce this.

Run `python3 -B -m unittest discover -s Tests -p 'test_chat_*.py'` and `make check`
after changing the harness. Use a new output directory for any changed corpus or implementation.

Model release dates come from the reviewed text catalog and are copied with their primary source
into `run.json`. Reports use that frozen metadata, never the current catalog or a checkpoint upload
date. Apple is system-managed; older runs without release metadata report “Not recorded”.

While downloads are arriving, use `--only-models ID ...` to schedule installed members of the
comparison. Keep the full `--models` list unchanged on every resume. Unscheduled models retain their
planned coverage and remain pending; they are never silently removed from the ranking denominator.

## Bounded application-strategy experiments

The [November 3 retry](../../docs/reports/app-strategies-2026-11-03.md) compares frozen controls
with separate memory-write tools, bounded saved-fact context and native session-cache probes.
Its [registration](experiments/app-strategies-2026-11-03/study.json) records model coverage,
promotion rules and a hard native-execution budget. Protocol or persistence failures are
distinguished from generated-answer failures. Small diagnostic subsets never replace the full
model comparison. The `no_writes` check rejects both create and replacement attempts, including
ones refused by storage.

The [November 4 integration follow-up](../../docs/reports/native-conversation-integration-2026-11-04.md)
validates Granite continuation through the production streaming helper, Ministral's publisher
formatter, and the remaining frozen Qwen controls. Its separate
[registration](experiments/native-integration-2026-11-04/study.json) preserves the original study's
stopping point and immutable evidence. Manual rubric review still applies when lexical checks pass.

The [cache and memory follow-up](../../docs/reports/cache-memory-2026-11-04.md) extends native
cache checks to Granite 3B and Ministral, separates first-message preparation spans, and tests
ranked retrieval and revision-safe writes with up to 10,000 synthetic saved facts.
