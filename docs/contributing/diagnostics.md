# Local diagnostics

Diagnostics are enabled by default. Use **Settings → General → Diagnostics → Export diagnostics**
soon after a problem. No developer mode or macOS permission is required. The JSON report can be
shared explicitly; nothing is uploaded. Clear diagnostics removes the app archive, and the toggle
stops new events. Exports that you saved elsewhere remain under your control.

`DiagnosticServices` owns one `DiagnosticRecorder` for the normal app lifetime. Features receive a
`DiagnosticSink`, never a directory or a global recorder. Automated launches and ordinary test
fixtures use disabled sinks or isolated temporary archives. `SilliesDiagnostics` cannot import UI,
capture, inference SDKs, Vault or app modules; the architecture checker enforces that boundary.

Use the typed `DiagnosticEvent` actions, phases, reasons and metrics. Extend those enums when a
new workflow needs coverage. Do not add arbitrary messages, dictionaries, payload dumps, stack
descriptions or error `userInfo`. Model/provider fields accept catalog identifiers; display names,
user text and paths must never enter them. `DiagnosticFailure` keeps a bounded type identity,
an allowlisted native error domain and its numeric code. It never serializes localized descriptions.

Record lifecycle changes, first-delivery milestones and cancellations at their owning boundary.
The admission coordinator records **why it preempts** work; Chat records user stop, speech detection,
recognition results, replay, mode/phase changes and timings. Never log per audio packet, token or
animation frame. Export does not open a microphone, read conversations or collect unrelated logs.

The recorder has a 256-event inbox and at most one utility drain. Filesystem work stays in the
journal actor; worker-entry assertions prevent disk work on the main queue. Export/clear suspend
new inbox admission briefly and drain accepted work before touching files. Overflow and temporarily
suppressed events are counted. The journal retains four files of up to 2 MB and reserves another
2 MB for one named atomic-pruning file. Startup removes an abandoned pruning file and repairs an
incomplete final record. Records older than seven days are removed on access, preserving newer
records in the same file. Export validates and re-encodes the bounded typed records; it does not
copy arbitrary file contents. Its own 10 MB cap prefers recent events.

Shutdown first joins startup, stops shared inference reporting, then drains the recorder. The
completion returns through `MainRunLoopDelivery`, including AppKit's modal termination run loop.
No timer, audio callback, UI disk write or unbounded task-per-event queue is introduced.

Run `scripts/test.sh --filter diagnostics`, `make check`, and the relevant headless race checks.
Tests cover rotation, retention, restart, partial writes, private error payloads, valid
JSON exports, concurrent producers, storage failure/retry, disabling, clearing and modal shutdown.
Use headless snapshots for Settings. Native save-dialog/activation checks require explicitly
requested visible testing.
