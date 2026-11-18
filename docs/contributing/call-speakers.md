# Recording-scoped call names

`CallSpeakerProviding` isolates app-specific metadata recognition. `ZoomCallSpeakerProvider`,
`TeamsCallSpeakerProvider`, and `MeetCallSpeakerProvider` own their vocabulary, accepted roles and
content scopes and optional `CallSpeakerVisualInterpreting` strategy. App composition injects their
factory into `CallWindowSpeakerReader`; neither capture nor the native tree walker switches on
call-app types. Providers receive typed metadata
and lazy, bounded roster/tile readers. They cannot retain native AX handles.

`CallWindowSpeakerReader` is a recording-owned actor. The native gateway stays in
`AccessibilityWindowSource.CallMetadata`, separate from tracking state and scheduling. Reads bind
to the selected process/window, use checked native IDs, reject ambiguous title/geometry fallback,
and share a 200 ms deadline, 1,500-node budget and depth/child limits. Editable subtrees are pruned
before text values are requested. Identified chat, caption and transcript containers are skipped.
Only recognized rosters or speaking tiles permit static-text value reads. Nothing from the tree
enters diagnostics. An app-owned `CallAccessibilityRegistry` shares manual-accessibility leases across recordings;
only the last lease restores a setting that Sillies enabled. Reader cleanup never waits on the main queue.

When a provider supplies verified tile identities and a visual interpreter but no explicit speaker,
`CallSpeakerHighlightReader` requests one transient image through its injected
`CallSpeakerImageCapturing` dependency. The native `CallSpeakerWindowCapture` filters the exact
process/window and crops to the participant tiles. `CallSpeakerVisualLayout` bounds capture to
64 tiles, 4,096 points per dimension and 4,194,304 pixels; tiles must cover at least 75% of the crop,
so widely separated thumbnails cannot pull shared documents into a large capture region. There
is no OCR, image encoding, saved video, network request or Zoom control interaction. Missing screen
capture permission returns unavailable evidence without opening a permission prompt.

`ZoomSpeakerHighlight` owns Zoom's observed outline color. The reusable bitmap adapter samples
border and interior points; pure `CallSpeakerBorder` policy requires a thin highlight on every edge
and rejects solid-colored video. Only one unmuted highlighted tile is accepted. The native reader
rechecks tile names, audio state, window and tile geometry after capture; a changed layout discards
the observation. Teams and Meet do not opt into this strategy. A different adapter can supply a
different interpreter without changing capture, tracking or transcript code.

This bounded visual fallback is the explicitly authorized exception to the repository's prohibition
on pixel/screenshot polling for meeting-speaker identification. It reuses the recording's skill clock;
there is no additional timer, screen-wide capture or per-frame producer. One native capture remains
admitted even if its awaiting task is cancelled. Pause invalidates delivery; stop clears native caches,
rejects late images and never waits for a pending screenshot to finish. Neither images nor names enter
the diagnostic archive.

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
Zoom roster completeness requires every AXRows entry to be readable and the ordered row identities
to remain unchanged across the read. The bounded native collection gateway checks the AXRows count
and returned payload together; a separate AXRowCount attribute is not required. Zoom 7.2.5 exposes
AXRows but does not expose AXRowCount on its participant outline.
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

An offline bundle audit on 14 November 2026 examined Zoom 7.2.5 (90525) and Teams
26304.1203.5314.5342 without launching either app. Zoom's 17 native language resources contain the
participant-list, computer-audio and active-speaker resource keys corresponding to the existing
English parser. Teams has 52 native language resources; those resources alone did not establish an
additional speaking-label schema. Resource presence does not establish how a live AX node combines
labels, identifies the local person or proves roster completeness. No translated parser rules or
Teams/Meet roster fallback were enabled from this evidence.

The [bounded audit metadata](../reports/data/call-resource-audit-2026-11-14.json) retains versions,
resource hashes and key counts, with no vocabulary tables or user content. The next compatibility
check still needs actual authorized call metadata: each provider's speaking indicator, local-role
annotation, roster completeness and unavailable/stop paths. Meet additionally needs its live browser
scope/indicator contract checked. Until then, the existing anonymous-label and manual-correction
paths remain the supported fallback.

A read-only check against an ongoing Zoom 7.2.5 group call on 18 November 2026 reproduced the
roster failure: AXRowCount was unsupported while AXRows returned 13 entries. Reading and
revalidating the row collection recovered all 13 names and the explicit local `(me)` identity.
The accessibility-only scans still returned no active-speaker evidence: the visible video tiles exposed
computer-audio and video state without the required active-speaker field. Roster recovery alone
does not establish speaker identity in a group call.

After explicit authorization, transient participant-strip samples exposed a three-point outline
with sRGB color `(72, 221, 92)`. A passive sample followed the highlighted identity through two
speaker changes. The subsequent production-reader/timeline probe recognized three distinct names
and resolved 14 stable transcript intervals over 24 observations; transition intervals remained
anonymous. No meeting audio or words were read by that probe, and no images or names were saved.
This establishes the name-evidence path against the active meeting, not an end-to-end check of
the already-running app's transcript: that instance was not replaced or restarted during the call.
Headless fixtures cover border ambiguity, muted/stale highlights, geometry bounds, cancellation,
late native completion and the resulting named transcript text. Teams and Meet still need their own
live qualification. Hidden tiles, unavailable captures and unrecognized visual styles remain anonymous.
