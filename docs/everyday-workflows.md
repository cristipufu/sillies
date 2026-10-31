# Everyday writing and retrieval

## Shortcuts and startup

Settings → Everyday Shortcuts configures skills, dictation, selection commands, the Vault, Stash search, recovery, and crew pause. Control–Option–Space holds to dictate; Control–Option–D starts/finishes toggle dictation. Existing customizations and cleared bindings are preserved. Conflicts and failed registrations are shown. The focused shortcut recorder is the only place that collects a shortcut key; Carbon registrations need no Input Monitoring. Launch at login is opt-in and reflects macOS approval status.

Window commands resolve the frontmost application's current window on a worker and revalidate focus before starting. Moving to another application during lookup cancels the command.

## Dictation

Focus a text field, press the shortcut, and wait for **Listening** before speaking. The indicator appears immediately while permissions/models prepare, without taking keyboard focus. Release the hold shortcut or press the toggle shortcut again to finish. Finish and Cancel also appear in the indicator. Dictation ends after five minutes. A quick release while still preparing cancels; it does not begin recording later.

The microphone and selected local speech model produce the transcript. Dictation does not save an audio recording. Automatic language detection on a multilingual model is appropriate for English/Romanian mixing; an explicit language choice is honored or reported unavailable. Recognition quality depends on the model, microphone, and speech. “Verbatim” skips cleanup but cannot undo normalization performed by the recognizer itself.

Light cleanup has 750 ms after recognition finalization. Unavailable, unsafe, or late cleanup falls back to the finalized transcript. A late model response never rewrites the destination. Names from the dictionary, numeric values, and technical tokens are protected. No automatic cleanup can guarantee semantic equivalence; the original remains available in recovery.

The personal dictionary passes hints to engines that support them. Optional “heard as” substitutions work across all providers, match whole words, and do not cascade. Entries apply to new meeting and dictation captures.

Accessibility enables insertion into compatible fields. Without it, text is ready to copy. Before inserting, Sillies rechecks the original application, field, window/document, selection, and surrounding context. If any changed, the result stays in recovery. Native replacement is preferred; a clipboard fallback snapshots all available representations up to 16 MB and restores only its own clipboard transaction. A newer user copy wins. Unsafe multiline fallback is copy-only; no Return or submit action is generated. If insertion cannot be confirmed, check the field before manually pasting to avoid duplication.

Writing recovery keeps the latest 20 dictations and selection edits separately from meeting retention. It stores original and final text, supports individual/all deletion, and reports storage failures. Pause/exit preserves completed speech as copy-only text. Explicit Cancel discards the active capture.

## Captures and Stash

Snap saves the image immediately. Background OCR later adds searchable text; failures can be retried. Search indexes full transcripts, OCR, notes, and Stashes on a worker and supports Romanian diacritics. Results are shown in pages; Show more reveals older matches. Long saved transcripts open in their own native scrolling window.

Search Pocket Stash captures the original destination before opening. Type to search, use arrows, and press Return to paste; Escape closes. Incompatible destinations offer Copy. The Vault also offers paste-back after being opened from a destination application. Nothing monitors clipboard history automatically.

Captures default to **Keep everything until I delete it**. Optional limits retain 200/500/1,000 unprotected captures. Deliberate Stashes and protected recordings are exempt. The retention dialog previews the deletion count; Clear all explicitly includes protected records and Stashes. Markdown export writes a folder per record with portable relative links and copies owned image/audio attachments. Referenced Stash files remain references, as they do in the Vault.

## Speakers and selection commands

Saved recordings expose source-scoped speaker names. Naming Speaker 2 in one source does not identify Speaker 2 in another. Renaming changes headers and regenerates notes; it never edits spoken sentences. Resetting a name restores the original label.

Shorten, Fix grammar, and Translate operate only on an explicit selection of up to 3,000 characters. They require Apple Intelligence and language support from its local model, independently of speech recognition support. English and Romanian are selectable translation targets; unavailable language support leaves the selection intact with an explanation. Edits have an eight-second deadline and share dictation's destination validation, one-insertion rule, and recovery history.

Custom commands, Vault question answering, and calendar assistance remain later work.

## Fast acceptance checks

`make check` covers domain, lifecycle, persistence, architecture, and native interaction budgets. Tests exercise late cleanup, changed focus/clipboard, single insertion, early release, cancellation, OCR suspension, retention, corrupt-history recovery, and full-text retrieval beyond the old preview limit. UI snapshot tests include compact, non-activating dictation recovery.

The opt-in `SpeechBenchmark dictate MODEL_ID STORE AUDIO_FILE...` feeds short prerecorded fixtures through the actual interactive provider with dictionary hints. It reports release-to-final-text separately from total duration and probes main-actor scheduling delay. Run English, Romanian, mixed-language, silence, and noisy-speech fixtures under `scripts/run-bounded-test.py`; model preparation may need a larger cold-start allowance. No multi-hour soak is required. End-to-end insertion additionally requires checking the intended destination apps; a speech benchmark cannot establish compatibility with every editor or browser.

`build/Sillies.app/Contents/MacOS/Sillies --writing-test` exercises actual Accessibility insertion and Command–V into an isolated editor process, including changed-caret rejection and Romanian/code preservation. It requires existing Accessibility/event-posting permission, never prompts for it, and uses the normal guarded clipboard transaction. Both processes have a 25-second watchdog and restore the previous application's focus. Native AX calls intentionally reject Sillies' own process: in-process AX setters bypass IPC and would call AppKit on the worker.
