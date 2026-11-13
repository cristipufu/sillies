# Native window tracking

`WorkspaceTracker` coordinates events and immediate geometry publication. `WorkspaceNotifications` owns subscriptions and forwards native window changes synchronously; `WorkspaceInputMonitor` owns input-monitor start/stop; `WorkspaceFocusSession` owns app identity and continuity during discovery. Tracker start/stop invalidates observation generations so previous workers cannot publish into a restarted session. `WindowTrackingSchedule` owns its timers and delayed discoveries; cancel them on pause, suspension, and termination. Pure visibility/geometry decisions belong in Core. `WindowRefreshScope` expresses focused versus application-wide discovery; active manipulation always uses the known window.

Inject a private application notification center when tests deliver deliberately invalid native window values. Never broadcast those synthetic notifications through `NotificationCenter.default`: AppKit's own observers may terminate the process before Sillies can validate the input. Keep valid native event integration checks on the real notification center.

Window tracking AX queries belong to `AccessibilityWindowSource` and its isolated worker. Explicit meeting recordings use `CallWindowSpeakerReader`, a separate recording-owned actor for bounded speaking metadata from the verified bound window. Reuse the skill clock, suspend during manipulation/pause, invalidate late reads, prune editable/chat subtrees, and stop on every terminal path. Never archive its names or tree in diagnostics. Explicit dictation and selection commands use `AccessibilityTextAccess`, a separate isolated worker for bounded selection/context reads, destination revalidation, and native text insertion. These commands never monitor typed content. Clipboard snapshots and targeted Command–V events belong to `ClipboardPasteTransaction`; never send Return or retry an ambiguous insertion. Window-list reads belong exclusively to the metadata helper process. Move/resize/title/selection notifications cannot re-enumerate AX hierarchies. Preserve the last verified roles during transient failures. All scheduled/async results must be checked against current process, gesture, or generation ownership before publication.

A successful AX batch status does not verify its payload. `AccessibilityWindowInspection` validates the window role and readable, finite geometry. Application elements and error-only batches are unavailable reads, never proof of an empty window list. Both tracking and target caches preserve prior verified roles on unavailable reads; a genuinely verified empty list must still reject closed/minimized candidates.

`kCGWindowIsOnscreen` must explicitly be true before a window can be a visible target or occluder. CoreGraphics omits the key for ordered-out windows; treating omission as visible hides bound companions behind invisible backing windows. Keep this interpretation in `WindowServerSource.ParsedWindowEntry`, shared by tracking, targeting, and bound-window visibility.

Use `optionOnScreenOnly` for front-to-back occlusion order. `optionAll` is an unordered inventory and may place background apps ahead of the visible target. Bound-window existence uses one batched exact-ID lookup through the metadata helper; never infer closure from a truncated inventory, an unreadable response or a missing snapshot. A successful exact lookup that omits the target confirms closure. Preserve hidden/minimized windows and reject recycled identifiers owned by another process. System surfaces at Dock level and above can report screen-sized transparent bounds with alpha 1; do not treat those rectangles as opaque application occluders. Keep reads bounded and on the existing metadata worker, with no per-companion queries.

Applications may retain ordered-out backing windows after their document or meeting closes.
`AccessibilityWindowSource.BoundWindows` anchors an unambiguous AX identity while metadata is
available, then checks membership only for ordered-out targets on the existing skill clock.
Only a complete, readable inventory from a verified non-hidden application can retire that
identity. Hidden/minimized members, unavailable reads, truncated inventories and ambiguous initial
matches preserve the binding. Clear anchors with skill-clock ownership. Never enumerate this
hierarchy in response to move, resize, title or selection notifications.

Example: add a minimize rule to `WindowTransitionObservation`/`WindowTransitionEvaluation`, test it with virtual timestamps, then exercise native minimize/restore in the app fixture. Do not add character-dependent branches to tracking or use metadata polling to drive drag frames.

Run Core transition tests, `WindowTrackingScheduleTests`, window-candidate and visibility tests, the four `SmoothnessBudgetTests` paths, and `make check`. Native integration: `build/Sillies.app/Contents/MacOS/Sillies --window-test --without-accessibility`. Do not relax timing budgets to hide a regression.
