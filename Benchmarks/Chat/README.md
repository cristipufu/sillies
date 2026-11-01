# Local Chat evaluation

Can a small local model be a useful companion **and** a dependable agent? This suite tests the
configuration Sillies actually ships: its conversation service, prompts, native message roles,
tool adapters, persistent memories, Vault retrieval and context compaction.

It runs without windows, recording, access to your Vault, or changes to your app settings.
All records, people and saved memories are synthetic. Native Swift workers run the model;
a Python 3.11+ standard-library supervisor manages deadlines, receipts and scoring.
There is no Python inference runtime, cloud judge or additional dependency.

Read the [first seven-model comparison](../../docs/reports/local-chat-models-2026-11-01.md),
including raw evidence, measured limitations and the next integration work.

`fixtures` validates every seeded database without loading a model and runs in `make check`.
Screenshot fixtures include real tiny PNG attachments and synthetic OCR text, so the normal
screenshot category can retrieve them. This measures text-based screenshot retrieval, not vision.
Each inference case also runs the same preflight before admitting the model.

## What it covers

The initial corpus has **52 scenarios, 71 tool-profile cases and 105 turns per model**.

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
Three interrupted workers stop that model's current batch. Missing models remain visibly pending.

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
Choose these **before** starting a run. Corpus, evaluator, binaries, model list, deadlines and
machine conditions are hashed/frozen; changed inputs require a new output folder. Machine metadata
contains OS version/build, processor family, architecture, memory and logical processor count;
it contains no hostname, serial number or user identifier. Each worker's model revision and
environment must also match the first worker before another case is admitted. Apple's model assets
remain system-managed; an unchanged OS build cannot prove that Apple has not updated those assets.
A documentation-only commit does not invalidate identical binaries. The initial source commit
remains in the run metadata.

## Read the results honestly

`report.md` and `summary.json` show coverage, group/profile breakdowns, errors and latency.
Each `MODEL/cases/*.json` preserves the reply, partial output, actual executed tool calls and
arguments, stored memories, retrieved IDs, compaction, native requests, token measurements and
the checks that passed or failed. `events.jsonl` also preserves progress up to a hard timeout.
The tool wrapper records executed calls; duplicate-cache hits and calls rejected before execution
are not counted as executed calls. Their resulting generation errors remain in the receipts.

Keep these measures separate:

- **Behavior:** whether the right tools ran, a memory really persisted, sources were returned,
  compaction occurred, and generation completed. Do not turn "I'll remember that" into a pass.
- **Exact answer:** both the content and the requested short-answer format. A correct explanation
  can fail a request to return only a name; this is not automatically a factual error.
- **Lexical anchor:** a weak diagnostic, not semantic accuracy. A reply can contain "Everest"
  while contradicting it, hallucinating extra facts or repeating itself.
- **Semantic review:** judge the raw reply against the case rubric. Store an array in
  `reviews.json` with `model`, `job`, zero-based `turn`, `responseHash`, `verdict`
  (`pass`, `fail`, `uncertain`) and a short `note`. Reporting rejects stale or duplicate reviews.
  Report selection and coverage; unreviewed answers are not implicitly correct. Agent review is
  preliminary and should receive independent human review before release claims.

Regenerate with `python3 Benchmarks/Chat/benchmark.py report --output PATH`.
Publish an auditable compressed snapshot with `python3 Benchmarks/Chat/benchmark.py export
--output PATH --archive docs/reports/results.json.gz`. It includes configuration, metadata,
all case receipts and any semantic reviews; keep the full worker logs locally for diagnosis.
Do not rank models with unequal coverage, or hide failed/timeout cases from the denominator.
A failed compaction may fail a full case; subsequent turns still have explicit failure receipts.

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

## Extend it

Add a case to `cases/*.json`: unique ID, group, tool profiles, user turns, semantic rubrics and
objective checks. Optional `history`, `records`, `memories`, `owner` and `language` seed the fixture.
Expected answers and rubrics stay in the evaluator; the worker receives only whitelisted scenario
inputs. Never put gold answers in a model instruction to make the test easier.

Add a text provider through the [existing model guide](../../docs/contributing/text-models.md).
No model-specific benchmark switch or duplicate inference implementation is necessary.
Keep the Swift worker independent of AppKit and model SDKs; architecture checks enforce this.

Run `python3 -B -m unittest discover -s Tests -p 'test_chat_benchmark.py'` and `make check`
after changing the harness. Use a new output directory for any changed corpus or implementation.
