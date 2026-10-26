# Performance

## Implemented constraints

- Native AppKit, SwiftUI, and Core Animation for companions; no web runtime or game engine.
- A small transparent panel per enabled companion, with a foot- or hand-anchored vector rig and a mask that excludes the focused document. Side poses hang upright; no screen-sized animation surface exists.
- Attached native panel rectangles are cropped to the exterior edge too. A mask is not the input boundary: the focused title bar is physically outside each attached panel. Rig and transition pivots use the cropped contact offset.
- One shared motion clock, 60 Hz normally and 30 Hz in Low Power Mode. Elapsed-time evaluation keeps motion frame independent. The clock stops when no character is moving.
- One shared next-decision deadline. Static and sleeping poses have no application frame loop.
- Presentation transitions are finite Core Animation clips with completion callbacks and cancellation tokens, independent of behavior resets. They add no application frame loop or per-character timers.
- Play mode uses shared pointer monitors and vector-path hit testing. Transparent canvas and the native window border pass input through. Monitors stop when interaction is disabled, paused, or excluded.
- Core Animation handles gait, bracing, footwork, squash/stretch, dust, and body inertia. Position stays out of observed SwiftUI state.
- Window metadata is read on an isolated worker with at most one request in flight. Known window IDs allow targeted geometry queries. Full discovery happens on focus/click changes and periodic reconciliation; missing-window searches are bounded too.
- Without AX, the geometry heartbeat runs at 4 Hz; optional AX notifications reduce the heartbeat to 1 Hz. Native window notifications update attachment synchronously. A foreign-window drag is first confirmed by real geometry changes, then uses one temporary display link and current pointer geometry, up to the display's refresh rate (60 Hz in Low Power Mode). Metadata validates a confirmed gesture at 10 Hz.
- Pending and constrained gestures use bounded targeted metadata at up to 60 Hz while the pointer is moving. A failed header drag cannot invent window motion, and a constrained active drag never falls back to the idle heartbeat. A short, bounded release reconciliation handles the final frame of confirmed pointer gestures.
- Pausing stops the motion clock, behavior deadlines, geometry heartbeat, idle checks, and AX observation. Sleep and app exclusions also suspend active work.
- No screenshots, OCR, UI-tree scans, keyboard-content capture, or model inference are used for tracking.

## Validation

`make check` runs Swift and shell lint, core and app tests, a debug build, and pack validation. `make gui-check` adds lifecycle, presentation, real-window tracking, and live move/resize attachment checks.

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

`DragWindowSnapshot` discovers a bounded front-to-back window stack on a worker at pickup and on focus/stack changes. Pointer movement uses cached rectangles, with known geometry updates merged in immediately; it performs no WindowServer IPC. `DragWindowTargetResolver` coalesces asynchronous single-window metadata reads and rejects stale session/position replies. Mouse-up performs native validation and captures that ID before any return animation, so delayed metadata cannot select a different app. Pause, exclusions, disabling the crew, and termination cancel pending work.

The two shared highlight/wheel panels prepare their hidden views before interaction is enabled. The highlight uses a native Core Animation outline and a small, fixed-size app badge, with no window-sized SwiftUI tint. App icons are decoded by a worker into small cached bitmaps; SwiftUI bodies only read the cache. Unchanged models/frames and already-hidden HUD ordering are skipped. Automatic system popup animations are disabled. The wheel's dwell starts only after a valid target is entered, without a dead zone at the focused window's border. These services introduce no periodic poller.

```sh
build/Sillies.app/Contents/MacOS/Sillies --drop-return-test --without-accessibility --assert-drag-budget
```

This opt-in real-input test covers first window entry, highlight display, a dwell to open the skill wheel, selection, and release. It reports p95 and maximum display-link callback gaps during active dragging; the optional assertion rejects a gap above two 60 Hz frames (33 ms), intended for a display running at 60 Hz or higher. It uses owned windows, temporary settings, and existing event-posting access; it restores pointer/focus. It does not measure compositor presentation latency.

On the local M4 Pro/macOS 26.7.1 setup, comparable debug runs measured a maximum active-drag gap of 36.96 ms before this change and 12.84 ms afterward; p95 stayed near 8.4 ms. These are fixture measurements, not a guarantee for every app/display configuration.

For repeated slow entry over a real, already-running application:

```sh
build/Sillies.app/Contents/MacOS/Sillies --companion-drag-test --target-bundle com.mitchellh.ghostty --without-accessibility
```

This opt-in check drags a mascot slowly over the existing window border, stops two points inside, waits for the highlight/wheel, and repeats five times. It does not send keys, choose a skill, move the target window, or change its tabs. It verifies mascot input ownership before posting the gesture, stops if the target loses focus, and restores pointer/focus. Output distinguishes overall drag gaps from border/wheel gaps and, only with this diagnostic mode, times movement, cached hit testing, highlight, wheel, and release validation. No terminal contents are captured.

The final optimized build was also exercised over the existing Ghostty window with five slow crossings and a pause two points inside the border. Across 1,595 active drag frames, p95 callback spacing was 8.38 ms and the maximum was 20.81 ms. Cached pointer hit testing rounded to 0.00 ms at two-decimal precision; the maximum measured movement handler was 4.18 ms, highlight update 2.72 ms, and wheel update 0.50 ms. All five entries showed both the correct highlight and wheel. These app-level timings include scheduling noise and do not measure compositor latency.

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

The local suite passes 47 tests plus native lifecycle, presentation, window, and live-attachment checks. The opt-in `--interaction-test --without-accessibility` check posts real clicks, pickup, a 62×28-point drag, and release to both characters over a controlled background window; disabled Play passes the clicks through. It uses temporary preferences, restores pointer/focus, and skips without prompting if event-posting access is absent.

The optimized custom-header move/resize regression also passes after native panel cropping. Its top-edge click reached the target window and produced a verified 40-point height change: mean error 0.39 pt, p95 0.50 pt, maximum 7.00 pt over 200 contact samples. The same run measured move p95 8.07 pt and corner-resize p95 0.32 pt, with two stale fixture messages discarded and no confirmed-gesture rejections. This is local app-level geometry evidence, not a universal compositor-latency guarantee.

## Historical v0.2 release sample

October 25, 2026: Apple M4 Pro, 48 GiB RAM, macOS 26.7.1, optimized arm64 v0.2 build, two companions, a visible native playground, Calm mode, AX notifications explicitly disabled, normal idle policy, three-second startup warmup.

| Scenario | Sample interval | Average process CPU | Peak resident memory |
| --- | --- | --- | --- |
| Window following active | 15.1 seconds | 0.569% of one CPU core | 61.1 MiB |
| Paused, playground still visible | 10.5 seconds | 0.614% of one CPU core | 61.1 MiB |

The paused interval includes the pause UI transition; the visible native playground remains open. These are short process-only measurements, not battery or GPU results. WindowServer/compositor cost and long-session behavior need separate profiling.

Profiling removed companion-window notifications from the local window monitor, repeated ordering of already-visible panels, and replacement of mask layers during geometry updates. Raw window coordinates are excluded from SwiftUI observation; the UI observes only coarse attachment changes.
