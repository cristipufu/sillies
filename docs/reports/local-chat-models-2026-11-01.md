# Which local model fits Sillies Chat?

**First measured comparison · November 1, 2026 · seven models · 497 cases · 735 turns**

Gemma 4 26B A4B is the strongest agent candidate in this run: it passed 46 of 52 primary
scenarios and actually persisted all seven tested positive memory facts. It also exposed an
inference-adapter defect: thought-channel delimiters reached the visible response in 26 of 78
primary turns. It needs that integration fixed before becoming a polished default.

Qwen 3.5 4B is a promising faster option, with 37/52 scenarios and a 1.88-second median to first
text. Its automatic memory behavior is incomplete. Ministral 3 8B and Qwen 3.5 9B scored slightly
higher overall, with greater latency; one run cannot establish that a one- or two-case lead is stable.

Apple's current model **with our current prompts, tools and adapter** is not dependable enough
for this combined general-chat, Vault and automatic-memory workflow. It passed 13/52 scenarios,
often chose tools for ordinary knowledge questions, and made incorrect persistent memory writes.
This measures an app configuration, not the maximum capability of each model.

[Run the suite](../../Benchmarks/Chat/README.md) ·
[Download all synthetic evidence](data/local-chat-models-2026-11-01.json.gz)

## What was tested

The frozen corpus contains 52 scenarios, expanded to 71 cases and 105 turns per model by varying
available tools. Every model completed the same cases. There were no missing cases or discarded
generation failures. The primary comparison uses the app's five tools: Vault search, full-record
reading, conversation search, memory search and memory saving.

| Group | Scenarios | Examples |
| --- | ---: | --- |
| General knowledge | 9 | Mountains, geography, science, arithmetic, authors |
| Vault knowledge | 8 | Saved URLs, screenshot OCR, meeting owners/budgets, reading beyond a search excerpt |
| Mixed knowledge | 7 | Vault → world → earlier Vault result; world → Vault → world; both in one question |
| Identity | 5 | User versus mascot names; correcting an earlier assistant mistake |
| Memories | 10 | Automatic saves, corrections, recall, opt-outs, hypothetical and third-party statements |
| Context | 3 | Retaining corrected facts and topic continuity after compaction |
| Evidence | 2 | Instructions embedded in records; saved screenshots versus the live screen |
| Languages | 4 | Short Spanish, French, German and Romanian exchanges |
| Tool scaling | 4 | Same tasks with 0, 1, 3, 5, 8 or 12 tools |

The mixed cases deliberately distinguish Paris the city from a private project called Paris,
return to screenshot details after discussing photosynthesis, and ask about both a meeting owner
and a scientific concept in one message. An empty personal search must not prevent the next
general-knowledge answer.

Inference uses the production conversation service, prompts, role handling, tools, persistence,
compaction and native provider runtimes. Each scenario gets fresh temporary synthetic databases.
The worker never opens the user's Vault or changes the running app's model selection. Screenshot
fixtures have a real tiny image attachment and synthetic OCR; this tests retrieval, not vision.

## Quality results

An **automated case pass** requires every configured check across all its turns to pass. Checks
include executed tools, stored facts, source IDs, completed generation, exact short answers and
lexical anchors. This is a workflow contract score, **not a factual-accuracy percentage**.

| Model | All primary cases /52 | Vault /8 | Mixed /7 | Identity /5 | Positive persisted facts /7 | General content review /9 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Apple on-device | 13 | 3 | 0 | 1 | 2 | 4 |
| Qwen 3.5 2B | 31 | 3 | 4 | 3 | 0 | 7 |
| Qwen 3.5 4B | 37 | 5 | 3 | 3 | 1 | 9 |
| Qwen 3.5 9B | 38 | 4 | 5 | 3 | 1 | 9 |
| Gemma 4 E4B | 33 | 3 | 3 | 2 | 0 | 9 |
| Ministral 3 8B | 39 | 6 | 3 | 3 | 1 | 9 |
| Gemma 4 26B A4B | 46 | 6 | 5 | 5 | 7 | 9 |

The general-content column is a separate coding-agent review of the nine standalone knowledge
answers. It accepts correct content despite an extra sentence or unnecessary read-only tool call;
the original automated checks still penalize those violations. These are elementary questions,
not evidence of broad factual expertise. Apple's 0/9 automated general cases therefore does **not**
mean it answered all nine facts incorrectly. Qwen 2B did make factual mistakes, including naming
the Atlantic as the largest ocean and saying Earth's axial tilt changes throughout the year.

Content/task review covers the same 23 turns per model: all nine general questions plus the
identity, memory, mixed-topic and retrieval smoke scenarios. The 161 reviews include response
hashes, individual notes and the reviewer identity in the evidence archive. Pass counts were
Apple 14/23, Qwen 2B 15/23 (one uncertain), Qwen 4B 21/23, Qwen 9B 22/23, Gemma E4B 20/23,
Ministral 22/23 and Gemma 26B 23/23. This subset misses important failures elsewhere in the suite;
it excludes presentation quality and is preliminary agent review, not blind human assessment.

Raw protocol markers were not a check in the frozen corpus. A subsequent diagnostic found them
in **26/78 Gemma 26B primary replies**, and none of the other models' primary replies. They remain
in the archive and are an explicit readiness blocker; the original score has not been rewritten.
Similarly, a correct URL source card without the literal URL in the reply can fail a lexical
check even when retrieval succeeded. Read the individual receipts before interpreting a failure.

## What actually failed

### Apple: wrong actions behind plausible replies

In `identity-saved-user`, the human name was already Alex. Asked “What's your name?”, Apple
searched memories, called `save_memory(name: Pogo)`, and answered “I'm Pogo!”. The answer looks
correct; the persisted **human** name was now wrong. The tool result had explicitly identified
the facts as belonging to the human, so the earlier attribution change did not fully solve it.

In `memory-opt-out`, Apple saved a preference despite “do not remember or save that.” In
`memory-no-secret`, it saved a fictional temporary password explicitly marked “Do not store it.”
These are confirmed writes in isolated fixture databases, not guesses based on the reply.
The current automatic-memory configuration needs further work before it can be trusted.

Apple completed 63/78 primary turns: 11 failed with the app's tool-budget error, three with the
existing repetition error, and one with an unsupported-language error. Across all profiles it
had 22 failed turns out of 105. Other models completed all 105 turns without generation errors;
successful generation does not imply a correct answer or action.

Apple's own guidance describes limited world knowledge and recommends focused tasks and
verified source information. That is consistent with treating it cautiously here, but does
not establish that all observed failures are intrinsic to the model. Our prompting and tool
integration remain experimental variables. [Apple's on-device prompt-design guidance](https://developer.apple.com/videos/play/wwdc2025/248/).

### Smaller downloads: acknowledgement is not persistence

Qwen 2B and Gemma E4B passed none of the seven positive persisted-fact checks. Qwen 4B, Qwen 9B
and Ministral passed one each. Many could repeat a name from recent conversation without ever
saving it. Qwen 9B explicitly promised to remember Alex for future chats, but made no write.

Private retrieval also failed independently of general knowledge. Models sometimes said they
could not access private records despite having the appropriate tools. Some selected only the
meetings category when the answer was in a saved note. Others treated a short search excerpt as
the complete record. In `vault-read-followup`, Qwen 9B invented release code `v1.2`; the real
fixture contained `violet-42`, accessible through `read_vault_record`.

### Gemma 26B: strongest actions, unfinished protocol handling

Gemma 26B saved all tested positive facts and passed the opt-out, hypothetical and secret-memory
checks. It nevertheless failed `memory-recall-seeded`: `search_memories` returned the birthday
May 14, and the model replied that it could not see a birthday. **Search succeeded; use of the
returned evidence failed.**

It also searched conversation history instead of the Vault for the Paris project, skipped
retrieval for the private half of a combined general/private question, and failed to open the
full meeting record for the release-code follow-up.

Many tool-using replies included raw `<|channel>thought` / `<channel|>` delimiters. The current
[MLX stream consumer](../../Sources/SilliesTextInference/MLXTextRuntime.swift) forwards decoded
text chunks directly. Google documents that larger Gemma models can emit a thought channel
even with thinking disabled. Its protocol also distinguishes retaining thoughts within a
tool-calling turn from removing them between ordinary turns. This calls for proper channel
handling in the adapter and conversation representation, with chunk-boundary tests; deleting
a few strings from the displayed answer would not implement that contract.
[Google's Gemma 4 protocol documentation](https://ai.google.dev/gemma/docs/core/prompt-formatting-gemma4).

The empty thought blocks observed here do not prove that every future block will be empty.
The content score therefore must not be used to wave away this integration defect.

## Responsiveness

Measured on an **Apple M4 Pro, 48 GiB RAM, 14 logical processors**, macOS 26.7.2 build 25G332.
These are debug native helper runs during normal desktop use, not isolated hardware benchmarks.

| Model | First text p50 | First text p95 | Full turn p50 | Failed primary turns /78 |
| --- | ---: | ---: | ---: | ---: |
| Apple on-device | 2.04 s | 3.32 s | 2.26 s | 15 |
| Qwen 3.5 2B | 0.73 s | 2.92 s | 1.11 s | 0 |
| Qwen 3.5 4B | 1.88 s | 5.06 s | 2.32 s | 0 |
| Qwen 3.5 9B | 3.07 s | 7.81 s | 4.13 s | 0 |
| Gemma 4 E4B | 1.29 s | 5.20 s | 1.89 s | 0 |
| Ministral 3 8B | 3.05 s | 11.40 s | 4.06 s | 0 |
| Gemma 4 26B A4B | 4.00 s | 8.50 s | 4.47 s | 0 |

First text means the first nonempty delta received by the conversation service. It may be a
preamble or protocol marker, not the substantive answer. It does not measure rendered UI or
audible TTS. Timings include instrumentation and normal tool/persistence work. Percentiles use
successful turns; failure counts are reported separately. Initial turns may include loading,
later turns reuse the model, and Apple's assets may already be warm. These are not controlled
cold-start measurements or promises for other Macs.

All models passed the three context scenarios. Each started with **32 prior turns, 64 messages
and no compacted checkpoint**, causing three compaction generations before the answer. First
text for that backlog recovery took 5.78–5.95 s for Apple, 5.12–12.48 s for Qwen 2B, 7.80–8.16 s
for Qwen 4B, 13.88–14.09 s for Qwen 9B, 17.81–20.76 s for Gemma E4B, 11.50–12.01 s for
Ministral and 19.66–19.88 s for Gemma 26B. This exposes a recovery-latency cost; it does not mean
every normal turn performs three summaries. Routine incremental compaction and realistic
checkpointed histories need separate measurements.

## How many tools?

There is **no supported universal optimum** from four exploratory scenarios. Expanded profiles
use harmless synthetic distractors; they do not exercise an arbitrary collection of real tools.
Here is one fixed three-turn test at each tool count: screenshot retrieval → photosynthesis →
the test count in the earlier screenshot. Every cell requires all three turns to pass.

| Model | 1 tool | 3 tools | 5 tools | 8 tools | 12 tools |
| --- | --- | --- | --- | --- | --- |
| Apple | Fail | Fail | Fail | Fail | Fail |
| Qwen 2B | Fail | Pass | Pass | Pass | Pass |
| Qwen 4B | Fail | Fail | Fail | Pass | Fail |
| Qwen 9B | Pass | Pass | Pass | Pass | Pass |
| Gemma E4B | Pass | Pass | Pass | Fail | Pass |
| Ministral | Pass | Pass | Pass | Pass | Pass |
| Gemma 26B | Pass | Pass | Pass | Pass | Pass |

Qwen 4B, Qwen 9B, both Gemmas and Ministral passed the standalone Everest task at all six counts,
including zero. Apple failed its strict checks at every count; some replies still contained the
right fact. Gemma 26B saved the introduced name at every count offering `save_memory` (3/5/8/12).
No smaller model passed that whole memory task at those counts. Adding distractors did not show
a simple monotonic decline; tool count alone does not explain the observed failures.

The same initial saved-URLs request also appears in three app-profile scenarios. Qwen 2B searched
only once, Gemma E4B twice, and the others three times. Inputs matched after excluding session
identifiers. This illustrates variability, not a confidence interval. Repeat configurations
before choosing a default. Apple's zero-tool profile additionally changes its sampler, so it
is not a controlled tool-count-only comparison.

## Reproduce and audit

The measured baseline is **`68cbf3d`**. Corpus SHA-256:
`390a5bb78e4f30d67a1148698cff3e19061522dc4b5f983d236bf03250b7fb31`.
The archive contains binary, catalog and evaluator hashes; model revisions; native requests;
executed tool calls and arguments; replies and errors; stored facts; source IDs; token/timing
measurements; automated checks; and all 161 content reviews. Full event and worker logs remain
in `build/chat-benchmarks/comparison-2026-11-01-v2` on the development Mac.

All downloadable models used the catalog's pinned 4-bit artifacts, the app's 4096-token context
configuration, a 240-token reply cap, temperature 0.7, top-p 0.9, repetition penalty 1.08 and
thinking disabled. Apple used the system-managed model with the same context/reply limits,
greedy sampling with tools and stochastic sampling without them. The app caps tool execution
at four. Models were downloaded and verified before the final run. Apple asset revisions cannot
be pinned through this harness; its OS/build is recorded instead.

One repetition was run per case/profile, in bounded resumable 300-second batches with independent
60-second turn, 180-second case and 90-second startup deadlines. No production prompt or runtime
was changed during the comparison. A preliminary run uncovered a missing image attachment in
the screenshot fixture; that entire pilot was excluded, the fixture was repaired and preflighted,
and **all seven models were rerun**. No model-quality failures were selectively retried.

After completion, the harness gained machine-condition freezing and a check against changing
worker model metadata on resume. This does not retroactively change the historical configuration
or scores. Every recorded worker metadata event in this run was checked against its saved model
metadata and matched. Hardware identity in this report was read locally; no serial or hostname
is collected. Use a new output directory for experiments with the updated harness.

Validation after the harness changes: `make check` passed with 611 verified selected native
test completions across 18 runs, 49 Python tests (including 15 benchmark tests), all 52 fixture
preflights, architecture/package boundaries, localization and native helper checks. These checks
validate the software and harness, not model-answer quality. Visible GUI checks were not run.

Evidence archive SHA-256:
`a8ab1cadddb17c3f4d36b8f6a1bda358ceb89265258ac756bd893827037988b9`.

## Next engineering work

1. Implement native reasoning-channel separation, preserving the model's required state within a
   tool turn while keeping internal channels out of visible text, stored replies and speech.
2. Evaluate memory decision and provenance handling independently of conversational fluency.
   Include explicit opt-outs, corrections, owner identity and actual persisted state. Do not
   substitute case-specific output filters for correct instructions and write semantics.
3. Test clearer tool contracts and context representation for Vault versus conversation search,
   full-record follow-ups, and general/private questions in the same turn. Record whether a miss
   occurred in tool selection, retrieval or interpreting returned evidence.
4. Measure checkpointed incremental compaction and release-build first-substantive-answer latency,
   then run repeated bounded comparisons on more than one Mac. Keep TTS latency separate.
5. Add held-out paraphrases and larger independent fact/task sets before selecting a default.
   Keep this corpus frozen as a regression baseline and get independent human review.

The benchmark and report do not change the live app's model selection or claim these production
failures are fixed. They provide a reproducible basis for making and validating those changes.
