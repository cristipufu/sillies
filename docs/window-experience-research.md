# Window experience research — October 25, 2026

The first implementation missed the defining experience: it gated window geometry behind Accessibility, silently substituted the desktop, and lowered a top perch into the document when headroom was limited. Generic swaying also did not give a strong enough response to window manipulation.

## Sources and implications

- [Apple: Advances in macOS Security](https://developer.apple.com/videos/play/wwdc2019/701/) explains that Core Graphics exposes window size, position, IDs, and owner process metadata; sensitive names/sharing state are filtered without screen recording approval. Basic geometry tracking should not require screen capture or access to document contents.
- [Apple: CGWindowListCopyWindowInfo](https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo(_:_:)) documents both targeted window queries and the cost of generating system-wide dictionaries. Discover on focus changes, cache the window ID, and bound subsequent reads on a worker queue.
- [Apple Human Interface Guidelines: Motion](https://developer.apple.com/design/human-interface-guidelines/motion) emphasizes brief, purposeful feedback that follows the person's gesture and remains cancellable. The visible reaction should track the actual movement/resize, then settle immediately after release.
- [Apple: Global event monitors](https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:)) describes asynchronous delivery of copied events from other apps. The callback alone cannot guarantee attachment at display cadence; it establishes the gesture, while a temporary display link samples the current pointer.
- [Apple: What's new in AppKit, graphics](https://developer.apple.com/videos/play/wwdc2023/10054/) introduces display links tied to screens, windows, or views on macOS 14. Sillies uses a screen display link during external dragging and the playground's native animation.
- [pokoPet's usage guide](https://sungwon1ee.github.io/pokopet-support/) treats the frontmost window's top edge as ground. That is the product's baseline interaction, not an optional hidden feature.
- [Pets Therapy](https://pets-therapy.com/) demonstrates window-edge perching, distinct animal behaviors, and interactions. Variety needs event-specific acting, not only random horizontal wandering.

## Implemented response

Window edges are the default. Geometry works without Accessibility; optional AX notifications enrich focus/context tracking. Characters attach outside the actual window, use exterior sides for tall windows, and wait if no safe exterior surface exists. Desktop walking is an explicit setting.

The cat braces and scrambles; the ninja balances and performs quick footwork. A foot-anchored inertia transform responds to movement and resizing independently of the selected clip. Release triggers a squash/stretch landing and a short dust effect. New manipulations interrupt settling instead of waiting for a cooldown.

Side poses use handholds rather than rotated standing artwork. Bodies remain upright with feet dangling below, a fixed upper grip, and a secondary hand that moves during climbing. The character packs select hanging and vertical climbing through `ambient.wall`; body inertia is independent of the grip.

Live measurements revealed that asynchronous metadata lagged badly during motion even though the settled-window check passed. Native frame notifications now attach synchronously; foreign-window gestures use immediate pointer mapping with metadata as bounded validation. Separate native and cross-process regressions measure error while a window is actually moving or resizing. This design follows from the API behavior and the local measurements; it does not guarantee identical timing for every application's custom window constraints.

A native window playground makes the core experience discoverable and reviewable. The runtime window check verifies actual WindowServer geometry, top-edge anchors, resize/movement events, animation selection, exterior side placement, and close detection. Native view composites are exported without capturing other applications.

This research informs the implementation; it is not a claim that the app has won awards or that every OS/window-management configuration is already validated.

## Custom main-header regression

The Culprit example exposed an assumption in pointer prediction: a drag beginning near a window's top is not proof that its application started moving the window. Before the correction, the right main header remained stationary while companions followed the pointer, reaching 82.46 points of false attachment error in the local regression. Sillies now requires actual geometry changes before enabling pointer mapping. A held drag that becomes incompatible keeps live metadata sampling rather than dropping to the idle heartbeat. Time-based pointer history prevents high callback rates from prematurely discarding validation samples.

With Sillies completely stopped, an independent 48-point input trial moved Culprit's sidebar header by 48 points but moved its right main header by zero. With corrected tracking enabled, the right-header trial measured zero character/window-mask movement across 722 independent observations. Culprit's own main-header behavior is a separate application issue; this observation does not establish that every custom header is non-draggable.

[Tauri's window-customization documentation](https://v2.tauri.app/learn/window-customization/) states that a drag-region attribute applies to its own element and must be applied to draggable children individually. Culprit's source marks the header but leaves its flexible child spacer unmarked, consistent with the observed difference between its empty sidebar drag region and main header.

[Apple's native window hit-test API](https://developer.apple.com/documentation/appkit/nswindow/windownumber(at:belowwindowwithwindownumber:)) identifies the actual window beneath a point, honoring transparency and ignored mouse events. Sillies uses it beneath character artwork so all application windows, including inactive windows, retain input priority. The regression also checks actual WindowServer routing, rather than only checking a panel's `ignoresMouseEvents` property.
