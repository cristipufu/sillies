# Performance

## Implemented constraints

- Native AppKit, SwiftUI, and Core Animation for companions; no web runtime or game engine.
- A small transparent panel per enabled companion, with a foot- or hand-anchored vector rig and a mask that excludes the focused document. Side poses hang upright; no screen-sized animation surface exists.
- Attached native panel rectangles are cropped to the exterior edge too. A mask is not the input boundary: the focused title bar is physically outside each attached panel. Rig and transition pivots use the cropped contact offset.
- One shared display-linked motion clock, following the active companion's display refresh rate. Tweens sample the upcoming presentation time; pickup also samples the current pointer between mouse events and skips duplicate positions. Low Power Mode caps travel at 30 Hz and pickup at 60 Hz. The clock stops when no character is traveling or picked up.
- One shared next-decision deadline. Static and sleeping poses have no application frame loop.
- Presentation transitions are finite Core Animation clips with completion callbacks and cancellation tokens, independent of behavior resets. They add no application frame loop or per-character timers.
- Play mode uses shared pointer monitors and vector-path hit testing. Transparent canvas and the native window border pass input through. Monitors stop when interaction is disabled, paused, or excluded.
- Core Animation handles gait, bracing, footwork, squash/stretch, dust, and body inertia. Position stays out of observed SwiftUI state.
- Reconciliation preserves unchanged behavior clips. Window inertia continues from an analytical sample of the interrupted clip, including settling springs, instead of jumping to the old target or reading the presentation tree.
- Window metadata is read by a bundled helper process with bounded local-pipe requests; a worker thread alone still shares AppKit's internal WindowServer connection lock. The helper has no windows or Core Animation transactions, stops with the last tracking owner, and restarts after an I/O failure. The geometry worker keeps at most one request in flight. Known window IDs allow targeted geometry queries. Full discovery happens on focus/click changes and periodic reconciliation; missing-window searches are bounded too.
- Without AX, the geometry heartbeat runs at 4 Hz; optional AX notifications reduce the heartbeat to 1 Hz. Native window notifications update attachment synchronously. A foreign-window drag is first confirmed by real geometry changes, then uses one temporary display link and current pointer geometry, up to the display's refresh rate (60 Hz in Low Power Mode). Metadata validates a confirmed gesture at 10 Hz.
- Pending and constrained gestures use bounded targeted metadata at up to 60 Hz while the pointer is moving. A failed header drag cannot invent window motion, and a constrained active drag never falls back to the idle heartbeat. A short, bounded release reconciliation handles the final frame of confirmed pointer gestures.
- Pausing stops the motion clock, behavior deadlines, geometry heartbeat, idle checks, and AX observation. Sleep and app exclusions also suspend active work.
- No screenshots, OCR, UI-tree scans, keyboard-content capture, or model inference are used for tracking.

## Validation

`make check` runs Swift and shell lint, core and app tests, a debug build, and pack validation. `make gui-check` adds lifecycle, presentation, real-window tracking, and live move/resize attachment checks.

The structural budgets exercise all twelve bundled companions, including individual pickup paths. The full-crew move/resize/switch fixtures use wider windows to give every character a valid perch and explicitly select the approved full-crew budget (p50 ≤ 2.5 ms, p90 ≤ 3 ms). Individual pickup tests retain the standard 0.75/1.5 ms limits. They require actual samples and reject a single handler over one 120 Hz frame (8.33 ms), as well as enforcing p50/p90/p95 limits. Diagnostic samples use bounded storage and retain the worst stall even after old percentile samples roll out. AppKit tests run serially because they share application/window state. `DisplayFrameSequence` drives the structural checks through the native application event loop at display cadence, with workspace producers stopped so injected geometry is not overwritten by unrelated focus changes. Sending hundreds of panel updates in a single run-loop turn instead measured artificial transaction backpressure (sampled inside AppKit’s screen/layout queries). The full-crew fixtures let eight display frames present the newly constructed panels before collecting manipulation samples: profiling traced a repeatable initial 16–22 ms resize sample to AppKit waiting for its first CA fence, rather than ongoing resize work. Both budget profiles retain p95 ≤ 4 ms and a maximum of 8.33 ms. These checks measure synchronous handler work; live display-link gap measurements also include deferred layout and run-loop scheduling.

### Twelve-character crew

The eight additional rigs reuse Core Animation layers and the existing shared clocks. Catalog validation covers all twelve renderers; reaction checks cover standing, both hanging poses, interruption cleanup, and Reduce Motion. All twelve characters passed real click/pickup/release and animated drop/return checks, including quiet unselected returns and explicit Focus activation. Lifecycle, independent presentation, native minimize/restore, external move/resize, and stationary-header checks also passed.

Local optimized build, all twelve enabled, 120 Hz display:

| Check | Result |
| --- | --- |
| Native move/resize attachment error | 0.00 pt across 3,540 live samples |
| Native move/resize synchronous handler maxima | 0.30 / 0.35 ms |
| Native callback spacing, p95 / maximum | 8.46 / 20.96 ms |
| Real click/pickup/release callback spacing, p95 / maximum | 8.36 / 10.26 ms |
| Animated pickup/drop/return callback spacing, p95 / maximum | 8.38 / 19.97 ms across 1,216 frames |
| External move / corner resize / top resize error, p95 | 1.30 / 4.42 / 0.49 pt |
| External move / corner resize / top resize error, maximum | 1.76 / 9.50 / 7.00 pt |
| Stationary custom header | 0.00 pt motion across 3,984 samples |

Native and external drag fixtures carry independently calculated `PerchSpacing` slots through resizing: a crowded crew can legitimately redistribute as the available span changes. Subsequent expectations never use measured attachment positions. The lifecycle fixture checks available perch capacity on narrow windows and starts its continuous minimize assertion at the native `willMiniaturize` notification; AppKit may return from the request before that notification. Long input runs refresh a resting reaction between companions so a scripted click does not chase an ambient stroll; pickup interrupts that reaction normally and runs the character's animated clip.

Two complete debug `make check` runs passed 74 core and 65 app tests during development. Subsequent runs exceeded strict timing thresholds under the current desktop workload, including p50/p90 budgets; those failures remain a limitation of the local validation, and no thresholds were relaxed. A full optimized test run passed all 74 core tests and 64 of 65 app tests: the rapid window-switch fixture measured p50 0.99 ms and p90 1.64 ms against 0.75/1.50 ms limits, with a 1.74 ms maximum. Move, resize, and every individual pickup timing test passed in that run. The optimized GUI results above are separate measurements, not a claim of universal frame-perfect presentation.

### October 27, 2026 smoothness audit

The largest reproduced freeze was an internal connection-lock cycle: a background `CGWindowListCopyWindowInfo` call waited in `SLSConnectionSynchronizeSLSCATransaction`, while the main thread's Core Animation commit waited in `SLSConnectionSetLastSLSCATransaction`. The metadata call timed out around 500 ms. Synchronous handler measurements missed this because the stall occurred during the later animation commit. Sampling captured both stacks in the same process; other public window-list APIs used the same synchronization path.

All window-list reads now run in `SilliesWindowMetadata`, a small bundled and signed helper with its own WindowServer connection. Existing worker queues serialize requests over local pipes, with response-size and timeout bounds; they never wait on the UI thread. Pause, exclusions, disabling the crew, and termination release tracking ownership and stop the helper. EOF also stops it if the parent exits. Failed reads preserve the last tracked geometry. This adds no network service, screen capture, or new permission prompt. The test script builds the helper and provides its path to the test process.

Also removed fixed timer pacing for travel, redundant clip restarts, discontinuous inertia retargeting, repeated presentation snapshots during hit testing, and forced highlight-badge subtree layout during pickup/target changes. Surface updates share one visible-frame read per display per pass; they do not retain it across passes because [Apple documents that the usable area can change between calls](https://developer.apple.com/documentation/appkit/nsscreen/visibleframe). Finite transition completions and metadata replies use common/tracking/modal run-loop delivery. Vault loading/decoding runs on its I/O worker with early-mutation merging and modal-safe termination flushing. Speech setup runs off the main thread without holding the lock required by pause/stop while calling the Speech framework.

Native minimizing windows are excluded from stale metadata and geometry notifications throughout the Dock animation. The fixture checks the transition itself, not only its settled result. The external input fixture now behaves as a regular document application and always targets its custom draggable header.

Local release comparison, four fully animated companions, 120 Hz display:

| Check | Before process isolation | After process isolation |
| --- | --- | --- |
| Maximum callback gap, three consecutive native move/resize runs | 508.91 / 507.81 / 512.33 ms | 8.92 / 8.66 / 8.51 ms |
| Live attachment samples per run | 688 / 684 / 804 | 1,200 / 1,200 / 1,200 |
| Maximum attachment error | 0.00 pt when callbacks ran | 0.00 pt |
| Maximum synchronous move/resize handler | Below 0.5 ms | Below 0.6 ms |

The failures above explain why low handler times and zero settled-position error were insufficient evidence of smoothness. They are retained alongside the successful runs. The release lifecycle, presentation, window/minimize, native drag, real-input pickup, drop/return/Focus selection, external move/resize, and stationary-header fixtures all passed after process isolation.

After removing the unselected post-drop skill bar and simplifying HUD measurement, three release drop/return runs measured maximum callback gaps of 18.78 / 14.57 / 18.49 ms, with p95 at 8.38–8.40 ms across 364 / 363 / 365 frames. Unlike the older active-drag-only numbers, these samples include pickup, overlays, mouse-up, the complete return, and explicit Focus activation. All runs verified that unselected returns create no binding or skill bar. The final `make check` passed 74 core and 64 app tests, including retention of an already-running skill during an unselected drop.

The final rebuilt release also passed the full GUI matrix. Native move/resize recorded zero contact error across 1,200 live samples, a 14.11 ms maximum callback gap, and synchronous handlers below 0.94 ms. Real click/pickup/release across all four companions peaked at 8.49 ms. External custom-header movement measured 3.85 pt p95 error; corner/top resizing measured 0.35/0.49 pt p95, with 8 pt maxima. The stationary-header check recorded zero motion across 1,432 samples. These external peaks remain visible in the report rather than being hidden by settled-position checks.

Earlier debug input fixtures also passed: all four characters received actual clicks/pickup/drag/release; drop-return and skill selection measured a 9.01 ms maximum active-drag callback gap; external custom-header dragging measured 1.23 pt p95 error; corner/top resizing measured 0.37/0.49 pt p95 error. A non-draggable header produced zero phantom movement. Existing Sillies copies must be hidden during real-input fixtures to avoid competing companion panels.

These are app-level measurements on this machine, not GPU/compositor presentation or a guarantee of zero missed frames under every workload. Low Power Mode, mixed-refresh displays, live audio capture, and sustained foreign-app workloads need separate device testing.

The window check waits for actual WindowServer geometry to match the native target and stabilize. It verifies the focused window ID, top-edge feet, outside-document placement, resize/movement events, distinct brace/scramble clips, landing, upright hand-held side attachment, and close detection. It exports native Sillies-owned view composites without capturing other apps. The separate drag regression samples contact error during every native frame update; a settled-position check alone cannot reveal dragging lag.

```sh
build/Sillies.app/Contents/MacOS/Sillies --drag-latency-test --without-accessibility
build/Sillies.app/Contents/MacOS/Sillies --external-drag-test --without-accessibility
```

The external check is opt-in because it posts real mouse input. It requires already-granted event-posting access and skips without prompting when that access is absent. It launches a disposable native window in another process with a custom main header that calls `NSWindow.performDrag`, enables Play mode, and drags that header beneath the companion panels, as well as checking top/corner resizing. Add `--expect-stationary` to test a custom header that consumes input without moving the window: companions must remain still. The checks return gestures to their initial pointer location, restore the pointer, and exit. Fixture stdout supplies independent ground truth; production tracking uses its ordinary metadata/mouse path. Input stops if the fixture loses focus. The normal app does not post mouse input or require this permission.

For an explicitly selected, already-running real application, `--target-bundle <bundle-id> --target-header-fraction <0…1>` tests only header movement, using an independent metadata worker for ground truth. It restores focus/pointer and returns the drag to its initial location. `--expect-stationary` asserts that a non-draggable region causes no phantom motion. These real-app checks are opt-in and are excluded from `make check`.

```sh
make build
build/Sillies.app/Contents/MacOS/Sillies --performance-check --without-accessibility
```

The performance check uses temporary preferences, a real native playground, the bundled crew in Calm mode, a warmup, a 15-second passive window-following sample, and a 10-second paused sample. It prints average process CPU and peak resident memory, then exits. It does not measure compositor/GPU cost, battery life, or sustained dragging.

## Companion drag response

`DragWindowSnapshot` discovers a bounded front-to-back window stack on a worker at pickup and on focus/stack changes. Pointer movement uses cached rectangles, with known geometry updates merged in immediately; it performs no WindowServer IPC. `DragWindowTargetResolver` coalesces asynchronous single-window metadata reads and rejects stale session/position replies. For an explicit radial skill selection, mouse-up validates that the same native window remains underneath the menu before any return animation. Unselected drops skip release hit testing and deferred metadata entirely, return to the pickup perch, and create no skill bar. Pause, exclusions, disabling the crew, and termination cancel pending work.

The two shared highlight/wheel panels prepare their hidden views before interaction is enabled. HUD cards use explicit hosting-controller measurement and a current state value; [automatic hosting constraints are disabled](https://developer.apple.com/documentation/swiftui/nshostingcontroller/sizingoptions), avoiding redundant minimum/maximum layout probes. Wider proportional text still triggers a fresh size, while digit-only timer and audio updates reuse the cached dimensions. The highlight uses a native Core Animation outline and a small, fixed-size app badge, with no window-sized SwiftUI tint. App icons are decoded by a worker into small cached bitmaps; SwiftUI bodies only read the cache. Unchanged models/frames and already-hidden HUD ordering are skipped. Automatic system popup animations are disabled. The wheel's dwell starts only after a valid target is entered, without a dead zone at the focused window's border. These services introduce no periodic poller.

```sh
build/Sillies.app/Contents/MacOS/Sillies --drop-return-test --without-accessibility --assert-drag-budget
```

This opt-in real-input test covers first window entry, highlight display, a dwell to open the skill wheel, selection, and release. It checks quiet returns above and below the perch, including dismissal of an open wheel without a choice, and verifies that only an explicit Snap selection creates a binding and status card. It reports p95 and maximum display-link callback gaps through pickup, overlays, drop, and return; the optional assertion rejects a gap above two 60 Hz frames (33 ms), intended for a display running at 60 Hz or higher. It uses owned windows, temporary settings, and existing event-posting access; it restores pointer/focus. It does not measure compositor presentation latency.

On the local M4 Pro/macOS 26.7.1 setup, comparable debug runs measured a maximum active-drag gap of 36.96 ms before this change and 12.84 ms afterward; p95 stayed near 8.4 ms. These are fixture measurements, not a guarantee for every app/display configuration.

For repeated slow entry over a real, already-running application:

```sh
build/Sillies.app/Contents/MacOS/Sillies --companion-drag-test --target-bundle com.mitchellh.ghostty --without-accessibility
```

This opt-in check drags a mascot slowly over the existing window border, stops two points inside, waits for the highlight/wheel, and repeats five times. It does not send keys, choose a skill, move the target window, or change its tabs. It verifies mascot input ownership before posting the gesture, stops if the target loses focus, and restores pointer/focus. Output distinguishes overall drag gaps from border/wheel gaps and, only with this diagnostic mode, times movement, cached hit testing, highlight, wheel, and release validation. No terminal contents are captured.

An earlier optimized build was also exercised over the existing Ghostty window with five slow crossings and a pause two points inside the border. Across 1,595 active drag frames, p95 callback spacing was 8.38 ms and the maximum was 20.81 ms. Cached pointer hit testing rounded to 0.00 ms at two-decimal precision; the maximum measured movement handler was 4.18 ms, highlight update 2.72 ms, and wheel update 0.50 ms. All five entries showed both the correct highlight and wheel. These app-level timings include scheduling noise and do not measure compositor latency.

## Skills integration validation

October 27, 2026, local M4 Pro/macOS 26.7.1, twelve-character crew:

| Check | Result |
| --- | --- |
| Native window lifecycle | Focus, exterior geometry, move, resize, minimize, restore and close passed |
| Native live attachment | Maximum move and resize contact error 0.00 pt across 3,600 samples |
| Move handler | p50 0.26 ms, p95 0.37 ms, maximum 0.80 ms |
| Resize handler | p50 0.31 ms, p95 0.39 ms, maximum 0.44 ms |
| Move/resize display-link gaps | p95 8.47 ms, maximum 15.51 ms across 300 frames |
| Wheel, Snap selection and quiet drop returns | p95 8.35 ms, maximum 22.13 ms across 1,214 frames |
| Final release-build clicks, pickups, drags and releases, all twelve characters | p95 8.36 ms, maximum 9.45 ms across 467 frames |

The checks used owned native windows with AX disabled. An earlier debug input check failed its click assertion; a release run passed. A later release repeat failed with the cursor away from the commanded drag position; the final repeat passed all twelve characters. Failure diagnostics include pointer, target and event counts. Passing retries do not establish the causes of the earlier failures.

Later debug-suite runs, while an older Sillies instance was also running, exceeded interaction timing budgets. Temporary stage measurements localized the extra window-switch time to the first native panel move, and a process sample found AppKit waiting for a Core Animation fence in `NSWindow._setFrameCommon` → `NSWMWindowCoordinator.clearDisplayAffinityForWindow`. A longer 800-switch diagnostic also reached a 29.50 ms maximum. After gracefully stopping the older app, the final full `make check` passed: 78 Core tests, 73 app tests, formatting, signed build and all twelve packs. The opt-in model test runs separately as described below. This does not prove that concurrent instances alone caused the earlier delays. The production metrics and standard 40-switch test retain their original thresholds; temporary instrumentation and the longer diagnostic fixture were removed.

The opt-in local AI check feeds generated speech into two real on-device speech channels, encodes AAC, and generates Foundation Models notes while running the unchanged budgets for window move, resize, switch and companion drag. It passed in 7.94 seconds and transcribed the fixture through both channels. Notes retained both explicit commitments in the source. This check uses synthetic audio; it does not record a microphone or meeting application. See [skill validation](skills.md#validation) for the command and remaining live-call acceptance check.

The language-selector and buffering regression passes the full `make check`: 79 Core tests and 83 app tests, including all four interaction budgets, formatting, the signed build and twelve packs. Speech now normalizes variable callbacks into 100 ms chunks with a bounded 12-second input stream; the earlier callback-count limit could fill with only about a second of frequent microphone input. The updated real-model check repeats generated speech three times on two channels using approximately 10 ms input buffers, with AAC encoding and notes generation, and passes the unchanged interaction budgets in 24.82 seconds. A separate French-output check verifies translated summaries and both commitments with their owner and deadlines intact. Switching tests preserve both source drafts, buffer new speech, reject old recognizer callbacks and finish safely during a switch. Utility-window regressions cover attachment/drop exclusion, native lifecycle notifications, stale metadata after close and reopening.

The macOS 26-only visibility and transcript follow-up passes `make check` with 86 Core and 88 app tests, the signed build, and twelve packs. Bound-window tests cover rectangular occlusion, hiding/restoring mascot and HUD, preserving capture during invisibility, native window levels, and utility-window priority. Capture input now budgets queued duration per source instead of 128 callbacks; a regression drains 2,000 one-millisecond PCM buffers without losing samples and separately verifies bounded overload. Timeline tests cover late finals, disjoint partials, two-source chronology, and adjacent-range floating-point rounding. The real local-model workload passes all four unchanged interaction budgets in 24.80 seconds while retaining all nine sentences in each of two speech streams; French summaries and actions also pass. These tests do not provide acoustic echo cancellation or certify live Meet/Zoom capture through laptop speakers.

A locked-display run initially exposed an actor-isolation error in the off-main test watchdog. Its handler is now explicitly Sendable, as is the automated app-check watchdog. Display-driven checks were rerun after unlocking; no performance thresholds were changed. These checks still do not certify live meeting capture on every app/device combination.


All timings are local app-level measurements. Display-link gaps include scheduling delays and do not measure compositor presentation latency or establish universal smoothness guarantees.

## Interactive matrix

| Scenario | Inspect |
| --- | --- |
| Top edge with headroom | Feet on the actual outer border; document remains clear |
| Rapid move/resize | Immediate acting; feet ride the presented window; spring settling is interruptible |
| Tall or maximized window | Upright handholds, dangling feet, vertical climbs; waiting if no safe exterior surface exists |
| Switch apps/windows | Short appearance transition; no travel across document contents |
| Pause/all characters disabled | No motion/decision clock or geometry heartbeat |
| Minimize/close | Old attachment disappears; a newly focused window gets a fresh attachment |
| Negative-coordinate displays | Correct coordinate conversion and exterior orientation |
| Lock/sleep/wake | Work suspends and resumes |
| Low Power/Reduce Motion | Reduced animation work and no unwanted travel under Reduce Motion |

Use Instruments and Activity Monitor to measure Sillies, WindowServer, GPU/compositor work, and power under the same display scaling/refresh settings. Long battery and multi-display/fullscreen/Stage Manager testing remains separate from the local regression suite.

## Live attachment regression

On the local M4 Pro/macOS 26.7.1 setup, the original metadata-driven path reached 216.12 points of movement error and 244.60 points of resize error during the native live regression. With synchronous native geometry, the same check measured 0.00 points for both maxima over 598 contact samples, at a requested 120 Hz. These are app-level contact coordinates during actual native frame changes, not a measurement of compositor presentation latency.

The cross-process input check separately tests real title-bar dragging and corner resizing. Its 10-point p95 budget includes asynchronous fixture ground-truth delivery; messages older than 40 ms are discarded and counted. Special app constraints, tiling, fullscreen, display changes, and compositor timing still need interactive validation.

The optimized v0.3 release, with AX disabled, passed this separate-process check:

| Actual mouse gesture | Mean contact error | p95 | Maximum | Contact samples |
| --- | --- | --- | --- | --- |
| Title-bar move | 0.80 pt | 1.11 pt | 1.32 pt | 56 |
| Corner resize | 0.12 pt | 0.31 pt | 0.34 pt | 632 |

No stale ground-truth messages were discarded in this run. Move notifications are coalesced more heavily than resize notifications, so the sample counts differ. These measurements cover this native fixture and machine; they do not establish a universal latency bound for other applications.

The v0.4 release adds a Play-mode input regression with the pointer beneath a companion's transparent canvas:

| Actual mouse gesture, Play mode enabled | Mean contact error | p95 | Maximum | Contact samples |
| --- | --- | --- | --- | --- |
| Title-bar move beneath companion | 0.80 pt | 1.21 pt | 1.25 pt | 54 |
| Corner resize | 0.60 pt | 0.33 pt | 62.63 pt | 194 |
| Top resize beneath companion | 0.40 pt | 0.47 pt | 21.27 pt | 280 |

Seven stale fixture messages were discarded. All gestures produced real window changes and passed the sample-count/p95 budget. Sparse larger errors remain visible in the maximum column and test diagnostics; the p95 result does not imply zero lag in every frame. This regression establishes that transparent companion panels leave these native input targets accessible, while separately reporting attachment accuracy.

## v0.4.1 custom main-header correction

The fixture now uses a full-content window with a custom main header that hands dragging to WindowServer through `NSWindow.performDrag`. The optimized build measured:

| Gesture | Mean contact error | p95 | Maximum | Contact samples |
| --- | --- | --- | --- | --- |
| Custom main-header drag | 0.62 pt | 1.11 pt | 1.28 pt | 54 |
| Corner resize | 0.13 pt | 0.30 pt | 4.83 pt | 506 |
| Top resize | 0.36 pt | 0.48 pt | 7.00 pt | 216 |

One stale fixture message was discarded; 1,842 pointer updates ran with zero confirmed-gesture rejections. These are app-level contact errors on this machine, not compositor latency. Unlike the earlier standard-title-bar test, this exercises a custom main-view drag handoff. The non-draggable-header regression separately requires zero phantom pointer updates and less than 2 points of maximum character motion.

## v0.4.2 Play and input-boundary correction

Protecting every background application rectangle prevented deliberate companion interaction over ordinary document content. Protection now applies to headers and resize borders, while native alpha hit testing makes visible characters ready for the first click without hover registration. Returning from a surface with no usable path preserves distinct crew slots instead of stacking both characters at a midpoint. Enabling Play closes the menu-bar popover.

The v0.4.2 suite passed 47 tests plus native lifecycle, presentation, window, and live-attachment checks. The opt-in `--interaction-test --without-accessibility` check posts real clicks, pickup, a 62×28-point drag, and release to each enabled character over a controlled background window; disabled Play passes the clicks through. It uses temporary preferences, restores pointer/focus, and skips without prompting if event-posting access is absent.

The optimized custom-header move/resize regression also passes after native panel cropping. Its top-edge click reached the target window and produced a verified 40-point height change: mean error 0.39 pt, p95 0.50 pt, maximum 7.00 pt over 200 contact samples. The same run measured move p95 8.07 pt and corner-resize p95 0.32 pt, with two stale fixture messages discarded and no confirmed-gesture rejections. This is local app-level geometry evidence, not a universal compositor-latency guarantee.

## Historical v0.2 release sample

October 25, 2026: Apple M4 Pro, 48 GiB RAM, macOS 26.7.1, optimized arm64 v0.2 build, two companions, a visible native playground, Calm mode, AX notifications explicitly disabled, normal idle policy, three-second startup warmup.

| Scenario | Sample interval | Average process CPU | Peak resident memory |
| --- | --- | --- | --- |
| Window following active | 15.1 seconds | 0.569% of one CPU core | 61.1 MiB |
| Paused, playground still visible | 10.5 seconds | 0.614% of one CPU core | 61.1 MiB |

The paused interval includes the pause UI transition; the visible native playground remains open. These are short process-only measurements, not battery or GPU results. WindowServer/compositor cost and long-session behavior need separate profiling.

Profiling removed companion-window notifications from the local window monitor, repeated ordering of already-visible panels, and replacement of mask layers during geometry updates. Raw window coordinates are excluded from SwiftUI observation; the UI observes only coarse attachment changes.


## Speaker echo and live suggestion bubbles

October 27, 2026: the shared Listen/Participate path adds local WebRTC AEC3 on the existing serial audio worker. Deterministic delayed-echo/double-talk testing measured 20.83 dB echo reduction and 0.828 near-speaker waveform correlation. The 24-second real Apple speech regression preserved the separate local speaker’s sentence and produced no remote “report” or “Alex” text in the microphone transcript, while encoding the mixed AAC recording and passing all four unchanged interaction budgets (27.87 seconds total). These are synthetic audio measurements, not a live Meet/Zoom or room-acoustics guarantee.

`make check` passes 91 Core and 93 app tests. Bubble regressions verify one native panel is reused for replacement suggestions, no focus/input interception, utility tracking exclusion, native z-level, hide/restore and pause behavior, and only one SwiftUI content update across 120 anchor moves. Light and dark previews were rendered and visually checked. The small bubble background updates its Core Animation path directly; window movement never measures or regenerates its SwiftUI text.

## Paw panel positioning

October 28, 2026: reproduced the native status-item popover at WindowServer y = -292 with a 666-point window on a 1512 × 982 display. Its hosting controller was allowed to negotiate its size after presentation, leaving the top offscreen. `ControlCenterHostingController` now establishes the bounded scroll viewport, native view frame, and preferred size before presentation, with automatic hosting sizing disabled; the popover content size is set explicitly on every opening. Reusing the host on a shorter screen recalculates its height. The native fixed panel opens at y = 28 with the header fully visible. A regression verifies stable initial sizing, popover adoption, and shorter-screen reuse without measuring the full character grid.

October 30, 2026: an 8,192-character live transcript reproduced roughly 992 ms per release-build UI update, exceeding the 500 ms publication interval. The native transcript viewport replaces `ScrollViewReader` and the outer fallback scroll layout. Reading and selection hold a stable snapshot while capture continues; Jump to latest or returning to the bottom resumes following, including after viewport resizing. Automatic hosting sizing is disabled. Paragraph diffs retain native layout between changed passages, with literal Unicode/UTF-16 and newline regressions. UI budgets use the existing display-linked driver rather than issuing compositor flushes in an unpaced loop, which can accumulate artificial WindowServer backpressure. Populated Listen/Participate windows at both 640 × 760 and 560 × 640 remain subject to an 8 ms p95 update budget.

Transcript sources now use timestamp-indexed revisions and cache formatted passages. Preview publication visits only recent source tails and reuses unchanged previews; the complete transcript is rendered for saving. A four-hour history regression bounds publication work, including late revisions, Unicode, finalization, language markers, and newline boundaries. Pending UI progress coalesces without losing lifecycle events, and stops explicitly at finish/cancel.

The optional endurance check encodes ten simulated minutes through the real synchronization, WebRTC echo cancellation, and AAC writer while displaying updates over four hours of transcript history and repeatedly scrolling between the beginning and end of the viewport. It requires scroll-operation p95 below 16 ms. This accelerated fixture synthesizes transcript passages; it is not an hours-long live microphone or Apple speech-recognizer soak. Run it with `SILLIES_LONG_AUDIO_CHECK=1 bash scripts/test.sh --filter sustainedAudioEncodingKeepsTranscriptScrollingResponsive`.

Suggestion bubbles now measure each new question once and wrap its text, with no fixed-height spacer/footer. Geometry changes reuse that size until the question or available screen width changes. Native HUD levels place bubbles above peer companions while preserving normal/floating window ordering and utility-window priority. Regression tests cover compact/long suggestions, normal/floating layers, cached measurement during movement, and background resizing. Light/dark previews were visually checked.

Core tests and all new transcript/bubble/endurance checks pass. The full app suite still reports the existing window-move, resize, and switch budget failures on this machine; debug runs can also record isolated companion-drag stalls. The original interaction thresholds remain unchanged.

Following that investigation, the user approved a separate budget for the 12-mascot stress fixtures. Their move, resize, switch, and hide/restore assertions now explicitly select `Budget.fullCrew`: p50 ≤ 2.5 ms and p90 ≤ 3.0 ms, compared with the standard 0.75/1.5 ms limits. Both profiles retain p95 ≤ 4.0 ms and a maximum of one 120 Hz frame (8.33 ms). Single-mascot drag tests and callers that do not select a budget retain the standard limits. This changes the stress-test acceptance criteria; it does not change runtime scheduling or represent a performance optimization.


The architecture follow-up retained the standard single-mascot budget. Substage profiling located variable drag samples in AppKit native frame placement, including Window Manager/Core Animation fence synchronization; hit testing and target selection were not the dominant cost. Overlay panels now explicitly opt into `canJoinAllApplications`, and origin-only placement also uses `setFrame(..., display: false)`. Temporary instrumentation was removed after profiling. In the first complete follow-up run, all twelve individual drag cases passed; the sole failure was the 12-window switch median of 2.032 ms (p90 2.487 ms, p95 2.515 ms, max 2.538 ms). The approved full-crew median allowance was adjusted to 2.5 ms; its other limits remain unchanged. This allowance is a test-policy adjustment, not an optimization claim. Native timings remain sensitive to system load.

Final follow-up validation: `SILLIES_SKILL_UI_SNAPSHOTS=1 SILLIES_LONG_AUDIO_CHECK=1 make check` passed (102 Core, 5 persistence, and 110 app test entries, plus formatting, concurrency/build checks, and all 12 packs). All four interaction budgets passed. The accelerated 600-second audio/encoding fixture with four hours of transcript history measured 0.217 ms scroll p95. Live transcript update p95 was 4.61–5.34 ms across both sizes and Listen/Participate. The opt-in prerecorded dual-stream speech/AAC check also passed in 27 seconds. Minimum-size failure-state previews were visually inspected; the header, finish controls, transcript, and footer remain visible while overflowing options scroll separately. These checks do not certify multi-hour live-device sessions.

## Bounded architecture and audio stress checks

The architecture follow-up adds `make stress`: compilation happens first, then a separate process watchdog limits test execution to 90 seconds. It simulates workloads immediately instead of waiting for their represented duration. The final run completed 12 stress/lifecycle checks in about 23 seconds:

- 100,000 progress updates took 26 ms and retained one pending UI update and one scheduled delivery.
- 100,000 audio callbacks across 20 input-queue lifecycles took 115 ms. The callback-limited fixture peaked at 786,432 accounted PCM bytes; every cycle ended with zero pending packets/bytes and a released queue owner.
- A separate 64-channel fixture reached the 32 MiB byte cap before either the duration or callback cap, reported overload once, and released its queue after draining.
- Ten simulated minutes of synchronization, echo cancellation, and AAC encoding over four hours of transcript history completed in 22.6 seconds; native scroll p95 was 0.422 ms.
- Deterministic tests cover duplicate recognizer completions, immediate finalization deadlines, cancellation before delayed preparation returns, partial startup failure, lifecycle ordering, and cancelled UI deliveries.

Byte counters describe admitted PCM references and conservatively count each queued packet, even when fixtures reuse a sample. They are not whole-process RSS measurements. Deallocation assertions and zero-backlog checks enforce resource lifetimes without depending on allocator caching or a multi-hour wall-clock run.

The final `make check` passed 105 Core, 14 audio, 5 persistence, and 107 app test entries, the 23 syntax-checker fixtures, the signed debug build, and all 12 character packs. Live transcript update p95 ranged from 4.33 to 6.06 ms. All four native interaction budgets passed. An earlier run recorded one 9.64 ms companion-placement sample against the unchanged 8.33 ms maximum; the final full run passed. These native timing tests remain sensitive to concurrent system work.

The short prerecorded Apple Speech integration also passed in 27.2 seconds after the synchronization changes, preserving both streams and the AAC recording. It does not require a live microphone session.

The rebuilt release app passed the native focused-window fixture (move, resize, settlement, exterior placement, minimize/restore, and close with Accessibility disabled), and its Developer ID signature passed deep/strict verification.
