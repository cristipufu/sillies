# Native conversation integration — 4 November 2026

This follow-up implements two integration findings from the
[app-only study](app-strategies-2026-11-03.md): Granite 4.2 8B native continuation and Ministral 3
message normalization. Qwen 3.5 4B's frozen confirmation and reserved validation are now complete;
its experimental memory preload remains disabled. These are targeted integration checks, not a
replacement for the full model leaderboard.

The [registration](../../Benchmarks/Chat/experiments/native-integration-2026-11-04/study.json)
sets a separate 900-second native-execution budget, sequential runs, no downloads, and the original
frozen Qwen workers and rubrics. The original November 3 archives remain unchanged. Measurements use
one Apple M4 Pro Mac with 48 GiB RAM; no user records, running-app preferences or windows are used.

## Granite continuation

Ten matched follow-ups through the packaged release helper include the app's token-measurement
request, acknowledged deltas and completion receipt. Five synthetic questions run twice, alternating
the retained/rebuilt order. Both arms use identical messages, profiles, tools and native checkpoint
restrictions; the control omits session identity to request a rebuild. All twenty answers match the
expected exact values. A control-first pair re-primes the opening and verifies that it is unchanged.

| Warm follow-up | Rebuild each turn | Native continuation |
| --- | ---: | ---: |
| First text, median | 6.622 s | 0.224 s |
| First text, p95 | 8.453 s | 0.479 s |
| Completed reply, median | 6.670 s | 0.282 s |
| Completed reply, p95 | 8.528 s | 0.541 s |
| Prompt tokens processed | 2,048–2,049 | 22–23 |
| Prompt tokens reused | 0 | 2,026 |
| Exact correct answers | 10/10 | 10/10 |

P95 uses nearest rank; ten samples are a small diagnostic, not a population latency guarantee.
Process-cold opening first text was 22.842 s and 7.115 s in the two repetitions, including model
loading, full prefill and the opening answer. These are not isolated weight-loading measurements.
The follow-up comparison excludes those openings. The helper's MLX allocation high-water mark was
5,862,666,786 bytes; this is not whole-process RSS. The earlier 5.454 → 0.150 s native feasibility
probe did not include this app IPC path and ran separately; neither number replaces the published
whole-task leaderboard.

The model profile opts into the existing SDK's native `ChatSession`. The helper owns one bounded
session and admits only exact extensions of committed messages, session identity, instructions and
tool definitions. The SDK owns token reconciliation and safe cache rebuilds. We do not trim recurrent
state manually or alter prompts to obtain a cache hit.

Token measurement leaves the continuation intact. Both the app's reconstructed prompt and the actual
native-session prompt receive the same context admission limit. A generation error, context overflow,
changed history, compaction, model replacement or ended session releases affected state. Registry
pressure eviction and cancellation still stop the killable helper. A session-end control frame waits
for the acknowledged stream's final receipt; failed cleanup kills the worker without discarding an
already completed answer. Other active consumers can keep the weights loaded.
Opening another conversation during idle cleanup awaits that bounded control exchange instead of
returning a spurious busy error. A regression overlaps teardown and a new request.

Nine native controls preserve the expected answer and cache behavior: unchanged history and ending
an unrelated session retain reuse; edited history, changed instructions, changed tools, changed
session identity, ending the current session, context rejection and generation failure rebuild.
Every control includes token measurement before the next generation. All nine pass.

The native structured-message API does not represent separate private reasoning. Requests carrying
that active tool state use the existing full-request path, and generated private reasoning prevents
retaining a continuation that could not be reconstructed faithfully. Only Granite 8B opts into native
session caching; the other profiles preserve their existing behavior.

The implementation uses the pinned
[MLX ChatSession](https://github.com/ml-explore/mlx-swift-lm/blob/3b339ad6e3b3f44c8121ecff5131c7fd55e075e6/Libraries/MLXLMCommon/ChatSession.swift).
Its native session is private to a serial owner; the narrow SDK `Sendable` bridge is registered with
the architecture checker. No SDK dependencies or model weights changed.

## Ministral message normalization

The pinned conversion's template rejected consecutive user messages before model generation. Valid
app histories can contain those messages after an interruption or when a persisted human statement
precedes the next question. Joining only neighboring user messages would still leave interrupted tool
turns unsupported.

The adapter now selects the unchanged
[publisher template at revision 5b26027](https://huggingface.co/mistralai/Ministral-3-8B-Instruct-2512/resolve/5b26027e7b19eeb4b7352e1fed3926375dd2cb4d/chat_template.jinja),
which contains Mistral's message aggregation. This is consistent with
[Mistral's instruction normalization](https://github.com/mistralai/mistral-common/blob/main/src/mistral_common/protocol/instruct/normalize.py).
Empty assistant placeholders without tool calls are omitted only from this render; nonempty partial
answers, roles and tool results are preserved. Saved history is never rewritten.

The template's source revision, SHA-256 and Apache 2.0 attribution ship with the integration. The
packaging check rejects changed template bytes unless their reviewed origin is updated. The native
helper self-check exercises the actual resource using a tiny synthetic tokenizer, including
consecutive users, an empty interrupted assistant, interrupted tool results and a nonempty partial
answer. No weights or network are required for these regressions.

Four installed-model replays also complete without template errors. Consecutive users and the empty
assistant placeholder both produce the correct June 18 birthday; an interrupted tool turn correctly
attributes the checklist to Mina. The nonempty partial-answer replay produces a valid
`search_memories` call, not a final answer; this protocol probe does not execute that tool. Some
answers still use Markdown despite the app's plain-text instruction. The formatter fix is not a
claim that all conversational behavior is now correct.

## App-loop diagnostic cases

Both models complete the original eight scenarios through the actual Chat service, Vault, memory
writer and packaged streaming helper. No template, transport or generation errors occur. Ministral
passes six tasks; its previously failing birthday history now passes. It still omits the explicit
preference and name/correction writes. Granite has five unambiguous passes, two omitted-write failures
and one uncertain quotation response: it identifies fictional Ivo but unnecessarily questions the
given narrator attribution. That uncertainty is not silently counted as a pass. The earlier screen
had six Granite passes and five Ministral passes; these single stochastic runs are not a paired
estimate of a quality change.

Granite's real tool continuations reuse 1,577 tokens after conversation search and 1,597 after Vault
search, while returning the correct source-scoped answer and saved URL. Its second name turn reuses
1,587 tokens; the answer still fails the persistence rubric because it makes no save call. Caching
changes preparation cost, not the obligation to execute a requested memory write.

The uncertain quotation was generated with zero cached tokens. A separately
[registered diagnostic](../../Benchmarks/Chat/experiments/native-integration-2026-11-04/first-turn-validation.json)
compares three fresh native/raw pairs at temperature zero using the same delivered requests. Text,
semantic tool calls and processed-token counts match in all three pairs, including the correct
narrator answer, Everest and a saved-link search. Session IDs and tool-call IDs are not semantic
content. This supports first-turn integration equivalence in those controls; it does not replace
the uncertain stochastic result or change product sampling.

## Qwen frozen validation

| Comparison | Original control | Preloaded saved facts |
| --- | ---: | ---: |
| Initial twelve-task screen, November 3 | 7/12 | 10/12 |
| Confirmation repetition 1 | 8/12 | 10/12 |
| Confirmation repetition 2, now complete | 9/12 | 10/12 |
| Reserved validation, now complete | 4/6 | 4/6 |

All scores are full-rubric manual reviews bound to reply, tool and persisted-state evidence. Every
turn is reviewed; the reviewer is the implementing coding agent, not an independent or blinded
human assessor. The automatic candidate validation count was 5/6, but its Spanish preference case
made no memory write and gave an incorrect hull/floating explanation. It fails the frozen rubric.

Preloading repeats the older-name recall benefit and avoids unnecessary retrieval calls. Both arms
retain the correct hobby correction, opt-out, unchanged favorite-color provenance and screenshot
retrieval in validation. The candidate's hobby update uses the existing stable-key upsert rather than
passing the supplied identity/revision; the resulting identity and correction provenance are still
correct in this fixture. It does not establish compare-and-set reliability for other corrections.

The mixed Vault/general question remains unsuccessful in both arms. The control explains
photosynthesis but invents that the checklist has no owner; the candidate declines both parts.
These particular inputs contain no saved facts: the model instructions, messages, tools and decoding
settings are identical after excluding opaque session/turn IDs. This is observed generation variance,
not evidence that preloading caused the general-knowledge regression. Neither aggregate scores nor
that single difference establish a dependable improvement to the complete mixed-question workflow.
The narrower recall signal does not clear the study's conservative component-level promotion review,
so the policy stays experimental. No prompt tuning or case-specific output repair was added.

The resume guard initially rejected today's changed repository catalog. The frozen workers, helper,
evaluator, machine and cases were unchanged; only Granite/Ministral's repository profile metadata
had changed. Completion therefore used an identical evaluator copy with the original catalog from
the frozen worker bundle. The original resume checks passed without modification. The evidence
retains that failed preflight and the restored catalog provenance.

## Verification and evidence

`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make check BUILD_DIR=/tmp/sillies-native-integration-check`
passes on the final source: 714 Swift tests with checked completion receipts, 94 Python tests,
architecture and formatting checks, 74 benchmark fixtures, complete localization extraction,
packaged text/TTS helper self-checks, orphan-helper termination and catalog validation. All checks
are headless. The release helper used for native measurements also passed its packaged self-check.

The client-side idle-cleanup race fix was added after the frozen native runs and is covered by the
final deterministic transport tests. The measured native runtime, model profiles and task
instrumentation are unchanged. Native execution stopped at 597.6 of the separately registered
900 seconds after the required controls completed; no unbounded soak or full leaderboard rerun was
performed.

The [evidence bundle](data/native-conversation-integration-2026-11-04/README.md) contains the raw
native pairs, app-case archives, hash-bound reviews, five successful archive audits, source overlay,
execution ledger and final repository check receipt. The original study's 35 manifest checksums
still match. No commit, push, model download, dependency addition or running-app restart was made.
