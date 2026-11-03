# Long-lived Chat: bounded replies and background checkpoints

Conversation age no longer determines how much summarization happens before a reply. Foreground
preparation reads one checkpoint and one bounded recent page, measures a fitting prompt, and answers.
It cannot generate summaries: its injected capability exposes token measurement only.

This implements the follow-up to the [profile and agent-loop experiments](agent-profiles-2026-11-03.md).
Those experiments exposed repeated summaries on the reply path and 60-second boundary-case failures.
Their historical results remain unchanged. This report is a focused engineering validation, not a
replacement for the [full model leaderboard](../local-text-models.md).

## What changed

- The complete conversation remains in indexed SQLite storage. The UI and inference each use bounded
  pages. Recent verbatim turns remain eligible even after a background checkpoint summarizes them.
- Each model declares recent-message and checkpoint page limits alongside its existing token budgets.
  Foreground admission selects whole turns within those limits, preserves the latest question and
  never traverses a summary backlog. A single bounded context-recovery attempt remains available.
- One lifecycle-owned producer coalesces jobs by companion. Jobs contain identifiers, not transcripts.
  Each idle slice reads one bounded page, generates at most one summary and conditionally persists it.
  Interactive inference cancels and joins a running slice before taking the shared turn gate.
  A byte-limited page can advance with fewer messages than the usual count threshold, so long
  messages cannot permanently prevent an otherwise fitting checkpoint batch.
- Checkpoint writes compare source generations and revisions. Edits, resets and competing writes
  reject stale results. Presentation saves cannot overwrite a newer summary. A restart resumes from
  the last committed source cursor; failed or cancelled summaries never advance it.
- Partial-context instructions distinguish prior chats, saved personal facts and the Vault. Missing
  context should prompt conversation retrieval for earlier statements and shared decisions, rather
  than an assertion that the user never supplied the information. General knowledge remains available.

See [model profiles and ownership](../model-profiles.md#long-lived-conversations) for the precise
contracts, limits and contributor requirements. There are no model-name branches, expected-answer
filters or scenario-specific retrieval rules in this change.

## Fast scale and lifecycle controls

These use synthetic data and fake inference to isolate application work. They are headless and do
not exercise rendered display-frame timing. The final full check measured:

| Control | Observation |
| --- | --- |
| SQLite archive | 10,001 messages; all preserved and the earliest message still searchable |
| Repeated replies | 50 replies; exactly one checkpoint read and one bounded page per reply |
| Reply work with fake inference | p50 1.016 ms; p95 1.210 ms |
| Largest page returned | 8,016 encoded bytes in this fixture |
| Foreground summaries | 0 |
| Main-actor scheduling probe | Maximum 0.019 ms; this is scheduling latency, not a frame-time measurement |
| Resident-memory change over the 50 replies | +360,448 bytes; end-minus-start RSS, not peak memory or a leak proof |
| Blocked background summary preemption | 2.086 ms with fake inference |
| Context selection at increasing history size | 100, 10,000 and 100,000 messages; bounded message count and at most ten token measurements |
| Queue coalescing | 1,000 submissions for one conversation retain at most one pending job |
| Checkpoint resumption | Six slices across fresh storage connections; one source page and one summary per slice |

Additional regressions cover stale UI saves, checkpoint cursor regression, source edits/deletions,
clear, summary failure, cancellation, deadlines, byte-limited checkpoint batches, oversized stored rows, oversized tool evidence and
preserving recent verbatim details after a checkpoint. Tests use temporary stores and never touch
real conversation history. No multi-hour soak is required.

Final `make check` passed: verified completion of 676 selected Swift tests across 18 runs, 92 Python
checks, benchmark fixture validation, localization extraction, packaged helper self-checks, helper
parent-exit checks and catalog validation. Opt-in native controls below ran separately with checked
completion receipts and 120-second external deadlines.

## Native interruption controls

Apple M4 Pro, 48 GiB, macOS 26.7.2. Initial native controls use the debug test host with the packaged
release helper for downloaded inference. Each starts with 10,001 synthetic stored messages, requests
a short greeting, starts a native background summary, then interrupts it. No summary runs before
the first reply. These are one-off controls, not latency distributions.

| Model | Initial complete reply | Background cancellation / gate acquisition | Complete reply after interruption |
| --- | --- | --- | --- |
| Apple Intelligence | 2.628 s | 137 ms | 0.917 s |
| LFM2.5 24B A2B | 16.529 s | 110 ms | 2.190 s |
| Gemma 4 12B | 9.740 s | 106 ms | 5.482 s |

Initial timings include runtime preparation; they are not warm-inference numbers. The post-interruption
reply includes whatever recovery or helper reload the backend needs. Cancellation does not make the
next inference instantaneous. The simple greeting is not representative of tool-heavy questions.

The final native control also completes one real checkpoint and reopens the database to verify it
persisted. All three providers completed this lifecycle check:

| Model | Initial complete reply | Cancellation / gate acquisition | Complete next reply | Completed and persisted checkpoint |
| --- | --- | --- | --- | --- |
| Apple Intelligence | 1.552 s | 84 ms | 0.852 s | 2.042 s |
| LFM2.5 24B A2B | 13.969 s | 137 ms | 4.315 s | 21.151 s |
| Gemma 4 12B | 9.233 s | 43 ms | 6.100 s | 3.554 s |

**Persistence success is not a summary-quality pass.** The source slice contains only numbered
placeholder discussions. Apple invented unsupported claims about months of activity, discussion
frequency and user intent. LFM correctly reported that no explicit facts or decisions were supplied.
Gemma described the numbered messages but also characterized assistant placeholders as acknowledgements
or archiving; that interpretation is not directly established by the source. These observations are
retained in [the separate summary review](data/long-lived-chat-2026-11-03/native-summary-review.json).
No claim-specific filters were added. Summary faithfulness remains a quality limitation, even though
the original messages remain intact and searchable.

## Archive recall investigation

A separate release-build control reuses the previous 192-message boundary history and its three
questions: an old fact, a newer correction and an older owner. The factual answers and exact-format
requirements are unchanged. A new case explicitly allows archive retrieval and requires **zero
foreground summaries**, replacing the earlier implementation-specific requirement to compact first.
The plan and corpus were frozen before inference. Every result, including failures, is retained.

In the initial control all nine turns completed, with no timeout or foreground summary. Apple
retrieved all three correct facts but failed all three code/name-only format requirements. LFM
passed the recent correction and older-owner turns; on the first question it searched personal
memories and the Vault, never the conversation archive. Gemma passed the recent correction but
did not call tools for either older fact. Traces establish retrieval selection failures; they do not
establish that the data was lost or that a model is intrinsically incapable of recall.

The app instructions described omitted history as “personal details,” while shared project facts
were also being omitted. The follow-up clarifies that conversations contain earlier statements,
plans and decisions, and that an empty saved-memory search does not establish an empty conversation.
The same contracts apply to every backend. The source corpus and grading remain unchanged.

| Model | Initial strict turns passed | Follow-up strict turns passed | Initial → follow-up median first text |
| --- | --- | --- | --- |
| Apple Intelligence | 0/3 | 0/3 | 3.75 → 3.16 s |
| LFM2.5 24B A2B | 2/3 | 3/3 | 19.96 → 4.75 s |
| Gemma 4 12B | 1/3 | 1/3 | 15.42 → 16.49 s |

Apple's factual answers were correct in both runs; the requested exact format still failed. LFM now
searched the conversation for the first fact, and its third answer reused the owner already present
in that retrieved evidence. Its first turn still took **29.49 s to first text**, including initial
preparation and two tool rounds. The median must not hide that slow turn. Gemma still answered the
recent correction but made no retrieval call for the older facts. Both runs had zero foreground
summaries and zero timeout/error turns. This is one three-turn case per model, not a reliable general
speed ranking or independent held-out validation of the prompt change.

The scored follow-up binary precedes the final byte-limited batch eligibility fix. That fix affects
background maintenance, which this benchmark worker does not start; its foreground path and tool
contract are unchanged. Background persistence and cancellation have separate controls. No original
failure is replaced by a retry or by a diagnostic with a more explicit question.

The explicit-search Gemma diagnostic used the same archive and frozen binary, asking it to search
the earlier conversation. It called `search_conversation`, received the original statement and
correction, and answered exactly `violet-42`. First text took **38.47 s**. That verifies a working
native tool-dispatch/retrieval path for this input; it does not fix the implicit-lookup failures or
prove why the model omitted the tool. Prompt/context sensitivity and automatic tool selection remain
open quality issues, not evidence that Gemma is intrinsically incapable of archive search.

## Scope and limits

This architecture bounds foreground preparation and queued maintenance independently of transcript
age. It preserves the archive; it does not promise infinite disk space, perfect generated memories,
constant-time full-text search at arbitrary database sizes, or identical latency on every Mac.
An exceptionally large current message can still exceed model capacity and return a recoverable
error. Existing summaries can lag during sustained interactive use; archive retrieval remains
available. A source slice that cannot fit does not advance the cursor or discard its messages.

Native results are from one machine and one pass per control. Implementing-agent review is not
independent or blinded human review. No visible GUI test was run, and no app instance was restarted.
Inference and persistence run off the main actor; that alone is not proof of smooth rendered frames
under every workload. The existing interaction-budget suite supplies separate headless regression
coverage.

## Reproduction and evidence

The [evidence directory](data/long-lived-chat-2026-11-03/) contains the frozen plans and corpus,
release artifact and source hashes, native logs, check logs and compressed scored receipts with
evidence-bound reviews. The archive auditor reproduces recorded checks and metrics; it does not
certify semantic quality or statistical confidence.

Use `make check` for deterministic controls. The opt-in
`nativeLongHistoryAndCheckpointPreemption` test is described in the
[text-model contribution guide](../contributing/text-models.md#check-it). It uses existing weights,
an external test deadline and temporary conversation storage. Keep compilation and other inference
out of native timing runs, and report model preparation separately from repeated warm behavior.
