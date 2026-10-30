# Native window tracking

`WorkspaceTracker` coordinates events and immediate geometry publication. `WindowTrackingSchedule` owns its timers and delayed discoveries; cancel them on pause, suspension, and termination. Pure visibility/geometry decisions belong in Core. `WindowRefreshScope` expresses focused versus application-wide discovery; active manipulation always uses the known window.

AX queries belong to `AccessibilityWindowSource` and its isolated worker. Window-list reads belong exclusively to the metadata helper process. Move/resize/title/selection notifications cannot re-enumerate AX hierarchies. Preserve the last verified roles during transient failures. All scheduled/async results must be checked against current process, gesture, or generation ownership before publication.

Example: add a minimize rule to `WindowTransitionObservation`/`WindowTransitionEvaluation`, test it with virtual timestamps, then exercise native minimize/restore in the app fixture. Do not add character-dependent branches to tracking or use metadata polling to drive drag frames.

Run Core transition tests, `WindowTrackingScheduleTests`, window-candidate and visibility tests, the four `SmoothnessBudgetTests` paths, and `make check`. Native integration: `build/Sillies.app/Contents/MacOS/Sillies --window-test --without-accessibility`. Do not relax timing budgets to hide a regression.
