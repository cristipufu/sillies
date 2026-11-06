# Setup, discovery and configuration — implementation audit

Date: 6 November 2026. Scope: SET-01 through SET-07 from the product opportunities review.

## Experience delivered

| Area | Result |
| --- | --- |
| First run | A skippable three-step journey in the existing Settings window: companion, activity, preparation. Choices survive closing and reopening. Start here remains available from Settings and the menu bar. |
| Discovery | Direct Chat and Talk actions, plus clear instructions distinguishing double-click conversation from dragging onto a window for window skills. |
| Readiness | One shared capability inspection for Chat/Talk and setup. All requirements are visible together. Permission actions are explicit. Meeting summaries are optional; meetings use their own saved recognition language. |
| Model choice | Compatible installed models first, followed by reviewed text scores and size. Combined memory estimates reserve room for recognition/synthesis and use the runtime's text-allocation policy. Full catalogs remain available. |
| Trials | A bounded microphone test, a short voice preview, and Try Talk opening the real conversation flow. Preview transcripts are not persisted. Ready means configuration is available; it does not claim a successful physical-device trial. |
| Personalization | Separate per-companion language, voice, personality and optional reply model. Reset preserves other companions, app defaults, messages and memories. |
| Presentation | Existing colors, artwork, cards and window ownership; persistent navigation controls, a single scrolling content area, reduced-motion-aware transitions, selectable notices and all 22 shipped languages. Advanced choices stay collapsed; qualified model performance defaults remain automatic. |

## Audit and corrections

The review covered dependency boundaries, main-actor work, lifecycle ownership, stale async
results, corrupt preferences, model removal, recovery routes, layout and test infrastructure.

| Finding | Correction and evidence |
| --- | --- |
| Microphone preview released its coordinator before the final callback. | Retain it until teardown completes; the close-settings regression verifies completion and prevents overlapping capture. |
| Closing or navigating backward could leave a late launch pending. | Separate refresh/action generations; navigation and shutdown cancel owned work. Late-readiness regression verifies no session opens. |
| Another active session could silently reject setup's conversation launch. | Return a typed failure, keep setup recoverable and revalidate on retry. Both presentation and skill admission are covered. |
| Hotkeys could bypass a setup preview's local busy state. | Connect active/stopping previews to the shared skill/writing audio admission; another conversation or recording cannot start before teardown. |
| Profile updates could be dropped during a reply. | Store a pending update and apply it at a safe ready boundary. The current reply retains its original profile; its text is preserved. |
| Meeting checks could use the companion's language instead of meeting preferences. | Resolve the same saved language used by meeting capture; unsupported/missing selections remain actionable. |
| A companion-specific model failure could send the user to the unrelated app default. | Open the companion profile, and provide an explicit reset of only its model override. Regression preserves personality and other preferences. |
| Malformed saved profiles and removed voice/model choices needed recovery. | Validate loaded overrides independently, retain valid companions and present unavailable saved selections without invalid picker tags. |
| View referenced a concrete text-model owner for an identifier. | Use the injected presentation's fallback identifier. Architecture enforcement is unchanged. |
| Instrumented tests used an obsolete resource copy inside a test bundle. | The test runner now uses SwiftPM's supported debug resource path for current build products. The actual app also packages recommendation data explicitly. |

No inference, model verification, native window query or explicit file read was added to the UI
thread. Recommendation data loads on a utility task; model availability uses the existing async
ports. Preview shutdown joins the existing audio owners and uses modal-safe delivery during
termination. Shared model-installation controls and selection styling replace duplicated view logic.

## Validation

The following results cover the final implementation, including the audio-admission correction. Checks run headlessly and retain
completion receipts; no test is counted from process exit alone.

- `make check BUILD_DIR=build/setup-validation`: passed. Verified 847 tests across 20 runs, 112 Python checks, architecture and formatting checks, all 1,048 source strings across 22 catalogs, benchmark fixtures, helper self-tests, parent-exit checks and catalog validation. Test receipts: `build/test-results/run-3szhceni`.
- `make stress`: passed 231 tests across 13 runs, including the new setup lifecycle cases. Receipts: `build/test-results/run-e82i1k6a`.
- `make race-check`: passed 279 tests across 16 runs, with no race reports. Receipt groups: `run-9zvmd70v`, `run-l8ygwhrd`, `run-s97rwx5r`, `run-o024_oya`, `run-crtuvjr5` under `build/test-results`.
- Visual inspection: companion, activity, missing-capability and ready states at the minimum content size in light and dark appearances; companion profile previews.
- Packaging: the built app contains 12 revision-pinned recommendation entries and all 22 language bundles.

One initial instrumented window-destruction check timed out; it passed in isolation and in both subsequent full instrumented runs. No timing budget was changed.

Visible native activation/stacking, permission prompts, physical microphone input and audible voice
playback were not exercised. They require an explicit interactive check. Existing runtime checks
and injected-device regressions cover orchestration and teardown, not acoustic or visual behavior
on every Mac.

## Recommendation limits and extension

Scores come from the existing published comparison and apply only to the matching checkpoint
revision. They are not new evaluations. Memory use is an estimate. Voice language compatibility
is declared by the catalog; text-language quality is not automatically inferred from an English
description. The selected text backend still performs its real language-availability check.

See [Setup and companion preferences](../contributing/setup.md) for extension contracts and
[the text-model comparison](../local-text-models.md) for the underlying evidence.
