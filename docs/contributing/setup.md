# Setup and companion preferences

Sillies offers a short, resumable path in **Settings → Start here**: choose a companion,
choose an activity, and prepare only what it needs. Setup never starts capture, downloads a
model or changes the selected model without an explicit action. Companions alone need none
of those capabilities. Chat needs a reply model; Talk additionally needs microphone access,
recognition and a compatible voice. Meeting summaries are optional.

## Ownership

| Responsibility | Owner |
| --- | --- |
| Persisted steps and choices | `SetupJourney` |
| Readiness, recovery and launch cancellation | `SetupPresentation` |
| Shared Chat/Talk capability inspection | `ConversationReadiness` in `SilliesChat` |
| Meeting language and platform permissions | `SetupReadiness`, `SetupPermissions` |
| Bounded microphone and voice trials | `SetupAudioPreview` |
| Companion overrides, validation and reset | `CompanionPreferences` |
| Per-companion service construction | `ConversationComposition` |
| Catalog recommendations | `SetupModelSuggestions` |
| View rendering and installation actions | `SetupView`, `ModelInstallationControls` |

Keep capability checks side-effect free. `ConversationReadiness` supplies the same typed
checks to setup and session admission. A successful check means configuration is available;
only an actual interaction verifies generation, capture and playback. Permission requests
belong to a user action, never a readiness check. Meetings use their own saved recognition
language, independently of a companion's conversation language.

## Adding an activity or model

Add an activity to `SetupActivity`, declare its requirements in `SetupReadiness`, and wire
its explicit launch at app composition. Do not put device access or model logic in a view.
Use `SettingsDestination` for recovery and `SessionFailure` for a rejected launch. A failed
launch keeps setup open; cancellation invalidates pending work before it can open a session.

Model catalogs remain the source of supported voices, language identifiers, revisions,
download sizes and minimum memory. Setup prioritizes compatible installed models, then
reviewed text scores and smaller downloads. Text candidates use `TextModelMemoryBudget`,
with an additional estimate for the selected recognition and synthesis models when needed.
Estimates are guidance, not a guarantee of available memory or language quality.

`Resources/SetupRecommendations.json` contains scores from the published
[text model comparison](../local-text-models.md), tied to exact model revisions. It is bundled
with the app. Updating a checkpoint invalidates that score until reviewed evidence is added;
a new model does not require a setup registration switch. Text catalogs do not yet declare
machine-readable language coverage: runtime readiness checks the selected language, and the
suggestion shows the model's documented language description without claiming per-language
benchmark qualification. Voice recommendations use declared language support.

## Preferences and lifecycle

Character JSON remains immutable. UserDefaults stores small overrides by stable character ID:
conversation language, personality, provider-specific voice and optional reply model. Reset
removes only that companion's overrides. Model overrides resolve through an injected backend
selector and never mutate the app's default model. Malformed saved profiles fall back to the
pack's valid profile without discarding other companions' settings.

`ConversationSessions` forwards updated profiles to existing sessions. A session applies
them at a safe ready boundary; an in-flight reply keeps its original context and voice.
Active Talk must end before changing its capture language or voice. Full conversation history
and personal memories are independent of these preferences and are preserved.

Microphone trials last at most ten seconds; voice previews accept at most 240 characters.
Trials use the existing capture, recognition and speech ports and never save a transcript.
Closing/minimizing Settings, leaving setup, changing the activity, or terminating the app stops
the preview. Teardown retains the microphone coordinator until its final callback and joins
speech shutdown before another preview or conversation can begin. Termination completion
uses the modal-safe main-run-loop delivery path.

App composition also exposes the preview's active/stopping state through skill admission's
audio reservation. Hotkey dictation, window capture and Chat/Talk cannot acquire another audio
session until teardown releases that reservation; preview ownership is not confined to its view.

## Verification

Run `make check`. Focused headless tests live in `SetupLifecycleTests`, `SetupInterfaceTests`
and the profile-change regression in `ChatSessionTests`. They cover resumed choices, corrupt
preferences, capability failures, cancelled/stale readiness, busy admission, microphone
teardown, per-companion model isolation, memory estimates and light/dark minimum-size rendering.

Use `SILLIES_SKILL_UI_SNAPSHOTS=1` with `scripts/test.sh --filter setup` to export views without
showing windows. Update all shipped localization catalogs for new copy. Actual permission
prompts, physical audio and visible native-window interaction require an explicitly requested
interactive check; a rendered preview does not validate those behaviors.
