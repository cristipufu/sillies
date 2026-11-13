# Recording-scoped call names

`CallSpeakerProviding` isolates app-specific metadata recognition. `ZoomCallSpeakerProvider`,
`TeamsCallSpeakerProvider`, and `MeetCallSpeakerProvider` own their vocabulary, accepted roles and
content scopes. App composition injects their factory into `CallWindowSpeakerReader`; neither
capture nor the native tree walker switches on call-app types. Providers receive typed metadata
and lazy, bounded roster/tile readers. They cannot retain native AX handles.

`CallWindowSpeakerReader` is a recording-owned actor. The native gateway stays in
`AccessibilityWindowSource.CallMetadata`, separate from tracking state and scheduling. Reads bind
to the selected process/window, use checked native IDs, reject ambiguous title/geometry fallback,
and share a 200 ms deadline, 1,500-node budget and depth/child limits. Editable subtrees are pruned
before text values are requested. Identified chat, caption and transcript containers are skipped.
Only recognized rosters or speaking tiles permit static-text value reads. Nothing from the tree
enters diagnostics. An app-owned `CallAccessibilityRegistry` shares manual-accessibility leases across recordings;
only the last lease restores a setting that Sillies enabled. Reader cleanup never waits on the main queue.

`CallSpeakerMonitor` uses the existing one-second skill clock, with one outstanding read. It
suspends during pointer manipulation, observed frame movement, pause and unavailable snapshots.
Cancellation/generation checks reject late callbacks. Shutdown dispatches reader cleanup off the
main actor, including while AppKit is running a modal termination loop.

Capture validates process/window identity, freshness and the capture/resume epoch before mapping
monotonic observation times onto recording time. `CallSpeakerTimeline` is pure Core policy:
120 seconds / 512 observations maximum, 1.5-second evidence hold, 750 ms transition margins and
90% coverage by one consistent remote name. Conflicting remote indicators and acoustic overlap
remain anonymous. Microphone passages are never assigned remote names. The two-person fallback
requires an explicitly complete roster, exactly two unique participants and verified local identity.
Zoom roster completeness additionally requires readable, unchanged AXRowCount and all AXRows.
Visible tiles alone never establish completeness.

Participant names are capped at 80 characters and 1,024 UTF-8 bytes both before and after
normalization. Native labels and DOM class collections have separate byte/count bounds. Non-finite
native identifiers, invalid geometry and corrupted saved names take recoverable failure paths.

The original acoustic label and words remain in `TranscriptSegment`; the suggested name is separate
metadata. Vault corrections edit exact, unambiguous header prefixes in the current transcript, so
corrected words survive. Ambiguous shared headers fail with a review notice instead of silently saving a correction. Clearing a name persists suppression. Corrections, suppression and note
revision changes share the existing Vault field-edit transaction. Existing SQLite bodies decode
the optional metadata without a database migration or rewriting personal records.

## Evidence and limits

The providers use separate, app-owned parsers with typed participant and activity metadata.
Zoom and Teams recognize their explicit English accessibility schemas. Unrecognized localized
labels stay anonymous. There is no translated vocabulary resource or runtime rules-file loading.
Zoom preserves commas and parenthesized display names, rejects conflicting audio/speaking state,
and accepts complete rosters only after every row validates. Teams requires a complete status
label and rejects contradictory title/description identities from the same node.
Meet requires an HTTPS `meet.google.com` WebArea and the `v5h6Xc` indicator identifier exposed
by the application. Its identity parser rejects clock labels, room codes and chat statuses.
Interface identifiers are compatibility data; a UI change can make metadata unavailable.
Teams/Meet two-person roster inference stays unavailable until completeness can be proven.

Synthetic provider, window-binding, lifecycle, audio-bridge, correction and persistence regressions
run headlessly in `make check`, with producer/bridge tests also selected by stress and race runs.
They establish the handling of supplied metadata, not live compatibility or accuracy in real calls.
Live Zoom/Teams/Meet recordings and visible native workflows need separately authorized validation.
