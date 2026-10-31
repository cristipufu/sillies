# Interactive writing boundary

This target owns dictation and selection-command lifecycles. It depends on Core, Reasoning, and the provider-neutral Audio/Speech contracts. It cannot import AppKit, SwiftUI, SilliesApp, persistence, provider implementations, or model SDKs. Source and package dependency policies enforce the boundary for every new file.

Supply capture, language discovery, text transformation, insertion, preferences, recovery history, destination discovery, and event delivery explicitly. No default live adapters, service locators, or shared workflow owners. Native implementations and UI belong in SilliesApp; views observe session state and forward intentions. History/preferences protocols expose only what the workflows need, not their backing stores.

Preserve immediate nonactivating feedback, generation-checked cancellation, bounded cleanup, single insertion, and recoverable text. Never send Return or rewrite a field when delayed cleanup finishes. Capture updates are coalesced in Audio; the app supplies modal-safe delivery so termination can drain without a MainActor task.

Run SilliesWritingTests and native dictation/selection tests, then make check. Queue/callback changes also require make stress and make race-check. Tests use injected devices and insertion; never require permissions or real inference in default checks.

Each dictation attempt owns a `DictationRun`: destination, capture resources, settings snapshot, failures, and timing belong to that run. Check current-run ownership on both success and error paths after every suspension; stale successful destination capture still requires release. Capture callbacks and deadlines must carry their run. A native finish callback is consumed once. Retain finalized audio on its run until recovery history accepts its text; modal quit must also drain the gap before a queued delivery Task starts. Explicit cancellation discards pending capture; suspension/termination preserves it. Never let a late insertion acknowledgement change a newer run's result or timing.

`WritingHistoryRecording` exposes typed loading/saving/saved/failed state and a flush receipt. Saving remains asynchronous and must not delay insertion. The native history adapter retains unsaved text, coalesces writes, and retries loading or saving according to its storage state. Active writing views and history use the same warning and Retry action. Retrying persistence must never repeat text insertion.
