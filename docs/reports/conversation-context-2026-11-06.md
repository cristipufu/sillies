# Explicit Vault context and memory controls

Date: 6 November 2026. Scope: KNW-01 and MEM-01 through MEM-03, plus bounded native-model routing
investigation and headless validation. This report describes implementation and observed limits;
it is not a new model leaderboard or a guarantee of model accuracy.

## Product behavior

| Action | Result |
| --- | --- |
| Vault → Discuss with… | Opens the chosen companion's continuous Chat with that record selected. Preserves an existing draft; a busy conversation reports why it cannot accept the item. |
| Chat paperclip or Vault-row drop | Selects up to three records. Compact removable chips retain stable IDs across reopening. The current saved content is fetched for each turn. |
| Remove a chip | Stops automatic inclusion in later turns. Earlier quotations remain, and ordinary Vault search is still available. |
| Memories → Pinned | Manually author a small profile: four shared facts and four per companion. A local topic overrides the matching shared topic. Models cannot modify pinned facts. |
| Memories → Learned | Search existing learned facts, inspect source quotes, edit, forget and use existing memory receipts/Undo. Missing original messages receive an explanation. |
| Memories → Manage | Delete messages, learned memories, or both independently. Pinned facts and companion preferences remain; preferences have their existing separate reset action. |
| Reply details | Shows selected-item, included-fact and omitted-fact counts. Bounded context is not a promise that a model will use every fact correctly. |

Selected screenshots supply saved OCR/text; this change does not add image understanding. Search and
storage stay on their existing actors. No extra timer, background inference task, dependency, cloud
service or output-repair filter was introduced.

## Recording-language clarification

The reported unsupported-language message came from the separate text-reasoning availability check,
not from Parakeet's speech recognizer. Speech capture already used the selected speech model, but the
transcript UI displayed the raw notes error without identifying the affected feature. It also
styled the temporary availability check as a warning.

Listen, Participate and Record now distinguish checking, available and unavailable AI notes. The
compact notice states that transcription is unaffected; details explain which speech model is used
and provide a direct Local AI settings action. Returning to the recording details rechecks the
selected text model without restarting capture. The suggestions pane uses the same recovery notice.
Synthetic tests cover all three modes, a language change, continued capture and transcript access,
recovery after changing text-model availability, and cancellation. No language-specific workaround
or silent model switch was added.

## Closed-meeting warning follow-up

The reported Zoom recording retained a genuine `audioProcessing` failure: its input queue exceeded
a bound. The older stderr log confirms the overload but has no queue timing or limit identity, so
it cannot establish the original cause. The saved record belongs to the original companion; the
regression reproduces window closure with a failed capture and verifies that other companions'
bindings and completion records remain untouched.

The confirmed presentation defect was the completion source label. Detaching a closed window removed
the target used for the label, so the HUD fell back to “Microphone.” Completed sessions now use their
matching saved record's source. A finishing meeting without a target uses “Meeting”; an unrelated
cached record cannot supply its label. Genuine recording failures remain visible.

Live capture processing now uses user-initiated QoS, matching its microphone and application-audio
callbacks. Previously it used utility QoS. This corrects the scheduling mismatch; it does not prove
that priority was the cause of the reported overload. Apple's [QoS documentation](https://developer.apple.com/documentation/Dispatch/DispatchQoS)
describes the scheduling distinction and the energy trade-off. Buffer limits remain unchanged.

The shared capture input queue also drains a local autorelease pool after each packet, so temporary
Foundation/AVFoundation objects do not depend on an idle worker to be reclaimed. A synthetic
continuous-queue regression uses an explicitly pool-free worker and checks that 1,000 autoreleased
allocations retire between packets. This validates ownership independently of device speed; it is
not evidence that autorelease retention caused the reported incident. Apple's
[dispatch pool contract](https://developer.apple.com/documentation/dispatch/dispatchqueue/autoreleasefrequency/never)
explains the inherited default.

An overload emits six typed events through the existing opt-in rolling diagnostics: the limit
reached, pending packet/byte counts, queued audio duration, maximum queue wait and maximum processing
time. The pressure snapshot survives draining. No transcript, audio, device identity, window title,
extra timer or unbounded log is introduced. Queue tests exercise both callback and byte limits;
the duration budget has separate pure tests. Physical capture under contention still needs a real
call to establish whether the original overload is eliminated.

## Ownership and audit corrections

| Boundary | Implementation / correction |
| --- | --- |
| Core contracts | Stable bounded record selection, user-owned facts, explicit scope and revision, and typed data-removal operations. |
| Storage | Conversation schema 6 adds separate profile tables. Version-five upgrades preserve messages and drafts. Writes validate owner, scope and revision; deletion invalidates conversation handles and affected search work. |
| Context | Current evidence is quoted user-message data. Selection and profile survive recent-history reduction. Whole facts are omitted only when the model budget requires it; the stored profile remains intact. |
| Passage selection | Select within the actual 480-character excerpt budget. Truncating a 1,600-character passage afterward could discard the answer and was corrected. |
| Cache ownership | Stable source data preserves a reusable prefix. History and profile revisions invalidate both native continuation and downloaded prefix snapshots. |
| Presentation | Separate selected-record, profile, memory-search and persistence-operation owners. Late reads are rejected; accepted writes drain even after their view closes. |
| Vault picker | Its presentation owner retires selectable rows immediately when the query changes and rejects late results. Views forward search commands and render bounded headers. |
| Recovery | A failed “Discuss with…” action uses the shared selectable warning presentation, rather than copy-success feedback. Missing source-message navigation leaves Memories open and explains the missing message. |
| Shutdown | Committed mutation results are accepted once through the modal-safe delivery path. Late deletion completion cannot revive a finished session or flush through a stale handle. |
| Prompt identity | Storage scope is not a person's identity. The early format prefixed facts with `companion`; native controls exposed incorrect self-identification. Scope labels were removed from model input while retained in storage/UI. |

### Review of the complete change set

The subsequent review reproduced and corrected these additional end-user failures:

| Finding | Correction and regression coverage |
| --- | --- |
| A speech-model preparation failure disappeared when the user finished a session that never started capture. | Listen, Participate and Record retain the original failure in the saved record. The regression proves that no capture service starts and that shutdown still completes. |
| A completed recording could hide its capture warning because the view only inspected the active failure phase. | The presentation owns the completed failure separately from its lifecycle phase. A single completion method preserves transcript access, recording state and the readable warning. Light and dark minimum-size renders cover the result. |
| Cancelling an unfinished notes-availability check left “Checking” visible indefinitely. | Cancellation retires the check to an explicit unchecked state; speech preparation failures remain visible independently. |
| Restoring or clearing selected Vault items could retain an obsolete selection-limit warning. | Restoring selection retires the old warning before refreshing the current references. A previously failing test covers clearing a full selection. |
| Memory-source navigation described storage failures as missing messages; a missing message itself was reported as a changed conversation. | A typed missing-message error distinguishes deletion from stale handles and storage failures. Navigation retains the actual recoverable error; cancellation does not become a warning. |
| The custom Vault drag type lacked its app-bundle declaration. | Declare the exported data type in `Info.plist`. Native Transferable export/import preserves only the record ID and rejects malformed drop data. |

Capture updates and overload diagnostics now share a cohesive `AudioCaptureEvents` value instead of
adding another independent callback argument to the service constructor. Storage, UI and capture
remain separate owners, and the fixes add no output filters or special cases for a particular model.
Apple requires custom transfer types to have matching bundle declarations; see
[Transferable](https://developer.apple.com/documentation/coretransferable/transferable/).

Local crash-report review found no Sillies app or inference-helper reports dated 6 November. The latest
app report was the already-corrected native window-number conversion from 31 October. Earlier helper
reports exist; their absence today is not proof that every possible inference crash is eliminated.

## Native Apple investigation

All inputs are synthetic. Runs use temporary storage, actual native Foundation Models inference,
the same synthetic Vault note, bounded output and the app's tool adapter. The held-out and selected-
context cases create a fresh conversation owner per case. Early controls invoke the native backend
directly; selected-context controls also perform measured context admission.
Memory cases inspect persisted facts rather than accepting a verbal claim. Diagnostic-test success
means the run completed, not that its answers were correct. Raw observations are in
[the result directory](data/conversation-context-2026-11-06/).

| Control | Observation | Decision |
| --- | --- | --- |
| General questions without tools, short and app instructions | Everest, Tokyo and 7×8 answered directly. | The model has the required knowledge in these cases. |
| Full app tools, short and app instructions | Unnecessary private searches and some false “not found” answers. | A shorter prompt alone did not resolve routing. |
| Native session constructor and default sampling | Failures reproduced with SDK-native construction and sampling. | No evidence that transcript reconstruction or greedy sampling alone explains the issue. |
| Experimental general-question delegate | Improved the three initial general answers; fresh cases improved Brazil and mixed private/general requests. It adds an inference call and can still make unnecessary searches. | Kept test-only; no unconditional extra call in the app. |
| Fresh memory cases with and without the delegate | Both saved oolong correctly; both incorrectly saved a dessert after “don't remember this.” | This is an observed write-decision limitation, not a success. The helper did not resolve it. |
| Selected note and pinned name | Exposed source-selection and human/companion identity errors, prompting the scope-label correction. | Keep model quality separate from storage/presentation correctness. |
| Same four selected-context cases after the scope-label correction | Mentioned Alex for the human-name request and answered the mixed Tokyo/review question; still missed the single review question and called itself Alex. One identity question also wrote an unrelated learned fact. | Removing ambiguous app metadata was warranted but did not qualify an Apple routing/identity fix. |

These are small diagnostic controls on one Mac, not repeated statistical qualification. The
delegate's 160-token helper output also truncated one longer explanation. Full tools remained enabled
in both compared arms; a failure to find a Stash note sometimes came from selecting `links` as the
search category. No category filter was silently overridden.

The Apple routing gap therefore remains open. Neither the general-question helper nor a new automatic
memory policy is enabled by this change. User-authored pinned facts have reliable ownership and
persistence, but they do not guarantee that a model will use them correctly. The explicit-context
controls also tested a concise prompt and a no-tools arm: neither establishes reliable identity
handling. Do not describe this work as fixing all Apple answer-quality failures.

The [subsequent representation controls](native-context-representation-2026-11-06.md) add 24 native
requests comparing structured tool outputs and entity-attributed background data. Both candidates
still failed identity and opt-out requirements, so neither was enabled. Their raw observations,
persisted-state review and stop decision are retained separately from this initial investigation.

Apple documents automatic tool selection, the importance of concise tool descriptions and bounded
context, and the default inclusion of tool schemas in instructions. The newer tool-calling-mode API
is unavailable on the tested macOS 26.7.2 installation. See [tool calling](https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling),
[schema inclusion](https://developer.apple.com/documentation/foundationmodels/tool/includesschemaininstructions)
and [context management](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window).

## Validation

The native-window fixture intermittently retained a closed window under Thread Sanitizer. Scoping
its layer flush alone did not fix it; making the fixture borderless did not fix it either. The test
now posts an inert application-defined event after teardown, allowing the headless host to complete
an AppKit event cycle and drain its outer autorelease pool. All window-release and WindowServer
absence assertions, including their original deadline, remain. Ten diagnostic sanitizer runs then
passed all 60 teardown cases. Apple's [NSApplication lifecycle documentation](https://developer.apple.com/documentation/appkit/nsapplication)
describes its event-loop pool ownership. No private debugging API or visible window is retained in
the test implementation.

| Check | Result | Local completion receipts |
| --- | --- | --- |
| `make check BUILD_DIR=build/review-validation` | Passed after the complete review: 899 selected Swift tests across 20 runs, 112 Python tests, formatting, architecture boundaries, all 22 language catalogs, benchmark fixtures, packaged helper self-checks, helper parent-exit checks and bundled catalog validation. Native-model probes remain opt-in. | `build/test-results/run-qqa95gpu/verified.json` |
| Targeted review regressions | Passed: eight lifecycle/storage tests across three runs, plus the native Vault transfer test. Startup-failure persistence and stale selection warnings were reproduced before their fixes. | `build/test-results/run-e4p9v7on/verified.json`; `run-bhm5gwf1/verified.json` |
| `make stress` | Passed after review: 280 selected tests across 13 runs, including capture-buffer cleanup, queue bounds, lifecycle cancellation, transcript scrolling, context selection and memory persistence. | `build/test-results/run-67t66_q8/verified.json` |
| `make race-check` | Passed after review: 325 selected tests across 16 runs, with no reported data races. GPU tensor execution remains outside the sanitizer as documented by the runner; packaged GPU checks passed in `make check`. | `build/test-results/run-eybt05qz`, `run-ptvppjlh`, `run-h52hz0ph`, `run-gytxtv22`, `run-55x8p1ob`; each contains `verified.json`. |
| Interface rendering | Reviewed light/dark context chips, pinned facts, learned memories, deletion controls, and minimum-size transcript/suggestions notices. | Twelve previews in `build/context-previews/`. |

The final accelerated run encoded 600 seconds of synthetic audio with four hours of transcript
history; offscreen scroll p95 was **1.47 ms**. Its 100,000-callback resource test covered 20 capture
lifecycles in **0.111 seconds**, with peak queued PCM of **786,432 bytes** and no retained packets
after draining. These measure the synthetic workload and queue ownership, not physical device
latency, whole-process memory growth or real-screen frame delivery.

Validation used the signed debug bundle at `build/review-validation/Sillies.app`, including its
exported Vault transfer-type declaration and signature verification. Native tests remained headless; visible
stacking, real save-sheet interaction, physical microphone/speaker use and VoiceOver listening were
not exercised. The real-call capture overload and Apple answer-quality limitations described above
remain explicit follow-up validation items.
