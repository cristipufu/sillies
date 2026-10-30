# Development contracts

Read `AGENTS.md` and the relevant ownership contract before changing a subsystem. Extend the existing owner when adding a state transition. Introduce a new owner when a responsibility needs a different lifetime, dependency set, or reason to change.

| Responsibility | Owner | Contract |
| --- | --- | --- |
| Behavior, geometry, attachment transitions | `SilliesCore` | Value models; explicit time inputs; no AppKit, I/O, or timers |
| Session file format and atomic writes | `SilliesPersistence` | Depends only on Core; throws read/write failures; preserves saved keys and date format |
| Session construction and export | `SessionOrigin` / `SessionContent` / `SessionMetadata`, `SessionMarkdownFormatter` | Cohesive inputs; existing flat JSON keys; independent export formatting |
| Native surface placement | `CompanionSurfacePlacement` | One transaction, immutable environment, at most one placement per companion per surface pass |
| Companion menus and skill controls | `CompanionSkillControls` | Owns HUD/menu/stash wiring; stop invalidates pending feedback; calls skill commands through `SkillCoordinator` |
| Shared decision deadline | `CompanionDeadlineClock` | One common-mode timer; cancel on pause, exclusions, empty crew, and termination |
| Companion motion and pickup | `CompanionInstance` | Private state; callers use transition methods; shared clock samples movement |
| Native subscriptions | `WorkspaceNotifications` / `WorkspaceInputMonitor` | Explicit start/stop; synchronous native frame delivery; no duplicated subscriptions |
| Application focus | `WorkspaceFocusSession` | Identity, trackability, and continuity while window discovery is pending |
| Window discovery/publication | `WorkspaceTracker` and platform workers | Session generations reject stale worker callbacks; AX stays on its worker; window-list queries stay in the helper |
| Window metadata cache | `WindowTargetCache` | State lives inside a `Mutex`; no IPC under the lock; generation checks reject stale refreshes |
| Vault browsing and commands | `SessionVaultModel` | Owns selection, search, save/undo/delete, and cancellable feedback; views only render and forward actions |
| Speaker detection | `SilliesSpeech` / `SessionDiarization` / SDK adapter | Independent source identity, bounded history/pending phrases; failure preserves text |
| Model updates | `SilliesModelStore` / `SilliesModelValidation` | Artifact discovery, daily persistence, worker schema/inference validation, atomic version selection and rollback |
| Speech providers | `SilliesSpeech` + SDK adapter targets | Channels own independent decoding state; weights are shared; bounded queues and explicit finish/cancel |
| Model installation | `SilliesModelStore` | Pinned HTTPS artifacts, hashes, atomic publication, active-use leases; all I/O off main |
| Audio engine | `SilliesAudio` | Core + provider-neutral speech contracts + echo cancellation; capture/language contracts use package access; no app/UI imports |
| Tracking schedule | `WindowTrackingSchedule` | One owner for workspace timer slots and discovery retries; replacement invalidates old callbacks; explicit stop |
| Session failures and recovery | `SessionFailure` / `SessionRecovery` | Typed categories and actions; native adapters classify errors; user text never selects recovery |
| Audio capture interface | `SessionAudioCapture` and capture contract values | Consumers do not depend on the concrete capture implementation |
| Capture lifecycle | `AudioSessionLifecycle` / `CapturePreparation` | Explicit phases and virtual-time duration; startup cancellation; idempotent finalization |
| Queue-owned native state | `SerialQueueStorage` | Private reference state, runtime queue assertion on every access, Sendable results, no synchronous dispatch or state escape |
| Speech language lifecycle | `SessionSpeechPipeline` / `SpeechChannelGroup` | All mutable state on the supplied serial queue; cancellation rejects late results |
| Vault application state | `SessionVaultStore` | Merge early edits after loading; block metadata writes on failed loads; modal-safe flush |
| Preview memory and conversion | `VaultImageCache` / `VaultImageCodec` | Bounded cache on main; encoding, decoding and scaling on the I/O worker |
| Clipboard and note tasks | `VaultClipboard` / `VaultSummaryScheduler` | Explicit cancellation or generation checks prevent stale publication |

## Changing a boundary

State the user-visible behavior, owning type, inputs/outputs, and cancellation/error behavior before introducing a cross-subsystem dependency. Keep domain decisions in Core and native effects in the app. A protocol's payload types belong to its contract rather than a concrete implementation. Additional package targets should enforce an actual dependency boundary; the persistence target is an example.

For changes to saved data, preserve backward decoding and existing identifiers. Attachment names must be single nonempty path components and cannot refer to the metadata index. Use `VaultFileStorage.removeAttachment` for cleanup: it unlinks files or symlinks and refuses directories. Never use recursive directory removal for a filename read from metadata. Test missing, unreadable, and malformed storage separately. A failed load must remain a failure until a successful reload; a retry must preserve edits made while loading was unavailable. Atomic writes protect replacement, not the correctness of the snapshot being written.

For concurrency changes, document the actor, serial queue, or lock owning each mutable field. Assert queue confinement at worker entry points. Keep unchecked Sendable implementations small and audit callbacks, cancellation, and shutdown together. Main-actor completions needed during termination must use `MainRunLoopDelivery`.

## Verification

- Run `swift format` on changed Swift files and `make check` for behavior/platform changes.
- Pure model tests live in `SilliesCoreTests`; audio-only tests in `SilliesAudioTests`; file-format and storage tests live in `SilliesPersistenceTests`; native integration belongs in `SilliesAppTests`.
- Use `bash scripts/test.sh --filter <test-name>` for targeted checks. The script serializes native tests because they share AppKit and WindowServer state.
- Use the standard smoothness budget by default; only the 12-mascot stress fixtures select the explicitly approved `fullCrew` budget. Preserve both profiles' p95/frame-stall limits and the single-pass-placement assertions. Report measured budget failures explicitly; a structural refactor is not proof of a performance improvement.
- Run `make stress` for audio delivery, transcript UI, or speech lifecycle changes. It builds separately, then runs accelerated workloads and deterministic cancellation/timeout/reordered-callback tests under a 90-second process watchdog. No multi-hour wall-clock test is required. Queue metrics measure retained PCM bytes and pending work; weak-reference assertions verify lifecycle release. These bounds do not represent total process RSS or certify every device/recognizer behavior.
- Run `make race-check` for concurrency changes. It builds with Thread Sanitizer in `.build/thread-sanitizer`, then runs selected audio, delivery, and metadata lifecycle tests under a 90-second process watchdog. Any detected race fails the command. The build is separate from the execution limit; normal builds and frame-budget measurements are unaffected. The selection includes concurrent audio admission/shutdown, cancellation, language switching, native metadata-helper recovery, and concurrent cache access. It does not request live-device permissions or exercise every Apple SDK handle.
- Persistence and lifecycle changes must include termination and recovery checks. UI changes must preserve reading position, selection, input pass-through, and window ordering.

Keep refactors reviewable by responsibility. Add tests for behavioral boundaries and failure modes, rather than tests that assert private method names or line counts. Update architecture and extension documentation whenever the associated contract changes.

## Local contracts and automated boundaries

Focused instructions live beside [Core](../Sources/SilliesCore/AGENTS.md), [audio](../Sources/SilliesAudio/AGENTS.md), [persistence](../Sources/SilliesPersistence/AGENTS.md), [platform tracking](../Sources/SilliesApp/Platform/AGENTS.md), and [UI](../Sources/SilliesApp/UI/AGENTS.md). They include ownership examples and the relevant tests; the root contract still applies. No agent orchestration or worktree policy belongs to this app.

`make lint` compiles the architecture checker against SwiftParser/SwiftSyntax shipped with the selected Xcode toolchain. Its positive/negative fixtures run before checking production sources. Rules inspect imports, call expressions, worker-entry assertions, and enclosing detached closures; comments and multiline formatting do not create exemptions. Compiler targets enforce dependency direction. `UncheckedOwners.json` is an explicit audit inventory, not proof of race freedom: changing an owner's fields or callbacks requires reviewing its confinement and lifecycle tests. The syntax checker cannot resolve aliases or prove arbitrary control flow. Notification classification and interaction budgets are covered by behavioral tests instead of source-string presence checks.

The deterministic `SessionSummarizer` stays in Core; `SessionSummaryWorker` in the app owns detached execution. This keeps scheduling out of the domain module while ensuring large summarization requests do not run on the main actor.

Lifecycle changes should run the `audioLifecycle`, `audioCaptureSequence`, `workspaceNotifications`, and `workspaceFocusSequences` cases, all included in `make stress`. These cover 4,096 command sequences, failure/permission-preparation shutdown, duplicate finish subscribers, timeout cleanup, owner release, 100 subscription lifecycles, and 1,000 focus switches. Use injected clocks and controlled completion callbacks instead of time-based sleeps. Native SDK adapters still require integration checks; a model test alone does not verify SDK behavior.

Saved-format changes must pass `LegacySessionRecordTests`. The committed `Fixtures/*.json` files are hand-authored examples of the historical formats, frozen independently of the current encoder. Do not regenerate them from `SessionRecord`; add a new fixture when a supported format changes. Tests compare every historical field after repository load/save as well as the typed recovery migration. Keep the legacy `failureMessage` key readable by older app versions.

The `future-failures.json` fixture also protects unknown failure identifiers through load/save. Unsupported category/action values must preserve diagnostics without offering an unrecognized recovery command; malformed JSON types still fail. Export changes must pass the complete Markdown fixture, including section order, omission of empty sections, and explicit-locale language names.

Downloadable speech runtimes require Swift 6.2 or later. Use the repository scripts so Xcode is selected locally for XCTest/Swift Testing; do not change the global xcode-select setting.
