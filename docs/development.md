# Development contracts

Read `AGENTS.md` and the relevant ownership contract before changing a subsystem. Extend the existing owner when adding a state transition. Introduce a new owner when a responsibility needs a different lifetime, dependency set, or reason to change.

For an extension, start with the dedicated guide: [companions](contributing/companions.md),
[interactions](contributing/interactions.md), [skills](contributing/skills.md),
[speech models](contributing/speech-models.md), or [text models](contributing/text-models.md).
The repository's [contribution guide](../CONTRIBUTING.md), [security policy](../SECURITY.md),
[privacy policy](../PRIVACY.md), and [license notices](../THIRD_PARTY_NOTICES.md) describe the shared
contributor and user-facing obligations. Keep them aligned with changes in data handling or dependencies.

| Responsibility | Owner | Contract |
| --- | --- | --- |
| Behavior, geometry, attachment transitions | `SilliesCore` | Value models; explicit time inputs; no AppKit, I/O, or timers |
| Versioned storage and attachment commits | `SilliesPersistence` | SQLite bodies, headers, and FTS updates in one transaction; throws read/write failures |
| Paged Vault access and background admission | `SilliesVault` | No UI dependencies; explicit body reads; bounded cache; queued IDs |
| Interactive writing | `SilliesWriting` | Required capture, insertion, history, preferences and delivery ports; no UI/storage/provider implementations |
| Local reasoning | `SilliesReasoning` | Inject `LocalReasoning`; prompts and validation have no app/UI dependency |
| Live service construction | `App/Composition` | Instance-owned models and backend selection; required consumer dependencies |
| Session construction and export | `SessionOrigin` / `SessionContent` / `SessionMetadata`, `SessionMarkdownFormatter` | Cohesive inputs; existing flat JSON keys; independent export formatting |
| Native surface placement | `CompanionSurfacePlacement` | One transaction, immutable environment, at most one placement per companion per surface pass |
| Companion menus and skill controls | `CompanionSkillControls` | Owns HUD/menu/stash wiring; stop invalidates pending feedback; calls skill commands through `SkillCoordinator` |
| Shared decision deadline | `CompanionDeadlineClock` | One common-mode timer; cancel on pause, exclusions, empty crew, and termination |
| Playful choreography | Core scene director/layout/session + `PlayfulSceneCoordinator` | One finite cast timeline; JSON choices; existing shared clocks; cancel before native geometry reconciliation |
| Companion motion and pickup | `CompanionInstance` | Private state; callers use transition methods; shared clock samples movement |
| Native subscriptions | `WorkspaceNotifications` / `WorkspaceInputMonitor` | Explicit start/stop; synchronous native frame delivery; no duplicated subscriptions |
| Application focus | `WorkspaceFocusSession` | Identity, trackability, and continuity while window discovery is pending |
| Window discovery/publication | `WorkspaceTracker` and platform workers | Session generations reject stale worker callbacks; AX stays on its worker; window-list queries stay in the helper |
| Window metadata cache | `WindowTargetCache` | State lives inside a `Mutex`; no IPC under the lock; generation checks reject stale refreshes |
| Vault browsing and commands | `SessionVaultModel` / `VaultListing` | UI coordinates requests and selection; the pure listing owns merging and cursors; views forward actions |
| Speaker detection | `SilliesSpeech` / `SessionDiarization` / SDK adapter | Independent source identity, bounded history/pending phrases; failure preserves text |
| Model updates | `SilliesModelStore` / `SilliesModelValidation` | Artifact discovery, daily persistence, worker schema/inference validation, atomic version selection and rollback |
| Speech providers | `SilliesSpeech` + SDK adapter targets | Channels own independent decoding state; weights are shared; bounded queues and explicit finish/cancel |
| Text inference | `SilliesTextModels` / `SilliesTextInference` | Provider-neutral contracts; one isolated MLX helper, bounded context/IPC, explicit cancellation and idle release |
| Inference priority | `SilliesInference` | Speech preempts downloaded text; no overlapping text generations; dictation reserves resources until finalization |
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

Crash prevention has three layers: checked values at system/data boundaries, regression tests for malformed and transient inputs, and native lifecycle checks for user journeys. Swift integer conversion traps and forced unwraps are not recoverable with `do/catch`; validate before conversion. Use `NSWindow.windowServerID` for AppKit window numbers, including positive values wider than WindowServer's 32-bit identifier. The architecture checker rejects direct conversions and forced unwraps as well as forced tries/casts. It is a syntax check, not proof of runtime safety.

Every crash fix must include a regression for the reported failure input and a check of the real triggering workflow. `make check` includes `build/Sillies.app/Contents/MacOS/Sillies --app-window-test --without-accessibility` after building. This short, watchdog-bounded native check opens Settings and the Vault through the menu-bar actions, closes and reopens them, and checks that companions remain running and visible and never attach to app windows. Rendering a SwiftUI view alone does not exercise native activation or transient AppKit windows. Keep app preferences and Vault fixtures isolated in automated launches.

Packaging must fail if a required runtime is missing or its library path cannot be installed. `scripts/embed-sparkle.sh` owns the updater framework and its executable-relative search path. Its regression launches a small linked fixture after deleting the source artifacts, so a build-machine library cannot hide a broken bundle. `make check` also launches the actual packaged app.

State the user-visible behavior, owning type, inputs/outputs, and cancellation/error behavior before introducing a cross-subsystem dependency. Keep domain decisions in Core and native effects in the app. A protocol's payload types belong to its contract rather than a concrete implementation. Additional package targets should enforce an actual dependency boundary; the persistence target is an example.

SQLite is the initial Vault format for this unreleased app; no JSON archive migration is supported. Future schema changes must explicitly version storage and preserve identifiers. Attachment names must be single nonempty path components and cannot refer to the metadata index. Use `VaultFileStorage.removeAttachment` for cleanup: it unlinks files or symlinks and refuses directories. Never use recursive directory removal for a filename read from metadata. Test missing, unreadable, and malformed storage separately. A failed load must remain a failure until a successful reload; a retry must preserve edits made while loading was unavailable. Atomic writes protect replacement, not the correctness of the snapshot being written.

For concurrency changes, document the actor, serial queue, or lock owning each mutable field. Assert queue confinement at worker entry points. Keep unchecked Sendable implementations small and audit callbacks, cancellation, and shutdown together. Main-actor completions needed during termination must use `MainRunLoopDelivery`.

Vault mutations pass through `VaultWriteCoordinator`: one active commit and one pending batch of per-ID changes. `VaultDatabase` owns attachment ordering and its cleanup journal. Retry includes failed attachment payloads. Body, header, and search changes share a transaction; an update cannot recreate a deleted record. Listings contain headers only. Load a full record explicitly by ID, retain selected detail only while presented, and queue summaries by ID. `VaultSummaryScheduler` retains its occupied slot until canceled work returns. Export processes one body at a time. Short synthetic tests verify decoded/encoded body counts, retained bytes, cancellation, and failure recovery. Existing-record edits use field commands against current state; background completions include their processing revision. Cursor pagination and changed-ID refresh avoid re-reading loaded pages or unrelated selected details. Regression tests cover edits during modal quit and insertion/deletion between page reads.

Writing lifecycles live in `SilliesWriting`, behind explicit capture, insertion, history, preference, text transformation, and delivery contracts. Native writing tools depend on `WritingCompanionHost`, `RecordingActivity`, and supplied Vault/command services. Wire owners in `SilliesMain` and `App/Composition`. All reasoning consumers receive `any LocalReasoning` or a supplied operation closure. A feature must not construct a concrete reasoning service, use a singleton, or supply a live default backend. Tests may use the isolated helpers in `TestServiceComposition.swift`; those conveniences are absent from production. Per-attempt state belongs to `DictationRun`; every async success/error and native callback must retain and validate that owner. History exposes typed persistence state and flush receipts. Failed writes retain the latest text and have an explicit retry, surfaced in the existing writing UI. Tests cover cancel/restart with late successes/errors, duplicate stop callbacks, delayed insertion, and write recovery in the modal quit loop.

See [local text model extension contracts](local-text-models.md) and [speech provider contracts](local-speech-models.md) before adding a runtime or model.

## Verification

- Run `swift format` on changed Swift files and `make check` for behavior/platform changes. Use `make check BUILD_DIR=/tmp/sillies-verification` to avoid replacing a running app bundle. Native MLX builds require Xcode’s Metal toolchain; the packaged helper receives a real GPU-kernel check.
- After resolving a dependency/catalog change, regenerate `THIRD_PARTY_NOTICES.md` with `python3 scripts/third-party-notices.py`. Review enabled traits, nested native code, model provenance, and license terms. App packaging checks that the committed notices match the resolved local sources and bundles the complete document, Sillies' MIT license, and privacy policy. The generator performs no downloads. Offline notice-regression tests run with `make lint`.
- Pure model tests live in `SilliesCoreTests`; audio-only tests in `SilliesAudioTests`; file-format and storage tests live in `SilliesPersistenceTests`; paging/admission tests in `SilliesVaultTests`; reasoning tests in `SilliesReasoningTests`; isolated writing lifecycle tests in `SilliesWritingTests`; native integration belongs in `SilliesAppTests`.
- Use `bash scripts/test.sh --filter <test-name>` for targeted checks. The script serializes native tests because they share AppKit and WindowServer state.
- Use the standard smoothness budget by default; only the 12-mascot stress fixtures select the explicitly approved `fullCrew` budget. Preserve both profiles' p95/frame-stall limits and the single-pass-placement assertions. Report measured budget failures explicitly; a structural refactor is not proof of a performance improvement.
- Run `make stress` for audio delivery, transcript UI, or speech lifecycle changes. It builds separately, then runs accelerated workloads and deterministic cancellation/timeout/reordered-callback tests under a 90-second process watchdog. No multi-hour wall-clock test is required. Queue metrics measure retained PCM bytes and pending work; weak-reference assertions verify lifecycle release. These bounds do not represent total process RSS or certify every device/recognizer behavior.
- Run `make race-check` for concurrency changes. It builds with Thread Sanitizer in `.build/thread-sanitizer`, then runs selected audio, delivery, and metadata lifecycle tests under a 90-second process watchdog. Any detected race fails the command. The build is separate from the execution limit; normal builds and frame-budget measurements are unaffected. The selection includes concurrent audio admission/shutdown, cancellation, language switching, native metadata-helper recovery, and concurrent cache access. It does not request live-device permissions or exercise every Apple SDK handle.
- Persistence and lifecycle changes must include termination and recovery checks. UI changes must preserve reading position, selection, input pass-through, and window ordering.
- Scene changes run the `playful` tests: virtual-time completion of every scene, exterior native bounds, pickup return slots, fixed prop grips, busy-crew exclusion, restart cleanup, and short native travel budgets. The downloaded-speech integration check also samples scene travel while two speech channels, optional speaker channels, and AAC encoding run. Visual exports remain opt-in; never replace bounded verification with a multi-hour soak.

Keep refactors reviewable by responsibility. Add tests for behavioral boundaries and failure modes, rather than tests that assert private method names or line counts. Update architecture and extension documentation whenever the associated contract changes.

## README artwork

The README uses production companion artwork, the skill wheel, the recording HUD, and the transcript
view over sample document/meeting backgrounds. These are composed previews, not captures of other
applications or real conversations. Regenerate candidates without replacing the running app:

```sh
SILLIES_README_PREVIEWS="$PWD/build/readme-previews" \
  bash scripts/test.sh --filter exportReadmePreviewCandidates
```

The opt-in fixture exports light/dark skill scenes, a crew sheet, and a light listening scene at 2×
resolution. It uses temporary hidden windows, sample text, and no live preferences or audio capture.
Without the environment variable, the fixture returns immediately. Review candidates before replacing
`docs/images/skills-light.png`, `docs/images/listening-light.png`, and `docs/images/crew.png`; those are
the selected README images. The app icon comes from `scripts/make-icon.swift`.

## Local contracts and automated boundaries

Focused instructions live beside [Core](../Sources/SilliesCore/AGENTS.md), [audio](../Sources/SilliesAudio/AGENTS.md), [persistence](../Sources/SilliesPersistence/AGENTS.md), [Vault](../Sources/SilliesVault/AGENTS.md), [reasoning](../Sources/SilliesReasoning/AGENTS.md), [writing](../Sources/SilliesWriting/AGENTS.md), [platform tracking](../Sources/SilliesApp/Platform/AGENTS.md), and [UI](../Sources/SilliesApp/UI/AGENTS.md). They include ownership examples and the relevant tests; the root contract still applies. No agent orchestration or worktree policy belongs to this app.

`make lint` compiles the architecture checker against SwiftParser/SwiftSyntax shipped with the selected Xcode toolchain. Its positive/negative fixtures run before checking production sources. Rules inspect package dependency lists, imports, concrete reasoning references, global service construction, default live dependencies, call expressions, worker-entry assertions, and enclosing detached closures; comments and multiline formatting do not create exemptions. Compiler targets enforce dependency direction. `UncheckedOwners.json` is an explicit audit inventory, not proof of race freedom: changing an owner's fields or callbacks requires reviewing its confinement and lifecycle tests. Direct aliases of concrete reasoning types are rejected; the syntax checker cannot perform full type resolution or prove arbitrary control flow. New production targets require an explicit dependency policy. Do not widen a policy to silence a failed check: put work in its existing owner or document a justified boundary change with negative fixtures. Notification classification and interaction budgets are covered by behavioral tests instead of source-string presence checks.

The deterministic `SessionSummarizer` stays in Core; `SessionSummaryWorker` in `SilliesReasoning` owns detached execution. This keeps scheduling out of the domain module while ensuring large summarization requests do not run on the main actor.

Lifecycle changes should run the `audioLifecycle`, `audioCaptureSequence`, `workspaceNotifications`, and `workspaceFocusSequences` cases, all included in `make stress`. These cover 4,096 command sequences, failure/permission-preparation shutdown, duplicate finish subscribers, timeout cleanup, owner release, 100 subscription lifecycles, and 1,000 focus switches. Use injected clocks and controlled completion callbacks instead of time-based sleeps. Native SDK adapters still require integration checks; a model test alone does not verify SDK behavior.

Record-codec changes must pass `SessionRecordCodecTests`. These fixtures test individual record fields, not an archive migration. The committed `Fixtures/*.json` files are hand-authored examples of the historical formats, frozen independently of the current encoder. Do not regenerate them from `SessionRecord`; add a new fixture when a supported format changes. Tests compare every source field after individual SQLite body round-trips and preserve typed recovery diagnostics.

The `future-failures.json` fixture also protects unknown failure identifiers through load/save. Unsupported category/action values must preserve diagnostics without offering an unrecognized recovery command; malformed JSON types still fail. Export changes must pass the complete Markdown fixture, including section order, omission of empty sections, and explicit-locale language names.

Downloadable speech runtimes require Swift 6.2 or later. Use the repository scripts so Xcode is selected locally for XCTest/Swift Testing; do not change the global xcode-select setting.
