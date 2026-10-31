# Add a skill

A skill is an explicitly invoked activity with a session lifecycle and, where appropriate, a result
saved in the Vault. It does not belong to a mascot renderer. The mascot observes status and performs
the pack's response while capture, processing, and storage have their own owners.

## Start here

| Concern | Location |
| --- | --- |
| Stable skill IDs, labels, capabilities, wheel membership | `Sources/SilliesCore/CompanionSkill.swift` |
| Session contract and typed contexts | `Sources/SilliesApp/Skills/ActiveSkillSession.swift` |
| Session construction and lifetime | `Sources/SilliesApp/Skills/SkillCoordinator.swift` |
| Command IDs and dispatch | `Sources/SilliesCore/AppCommand.swift`, `Sources/SilliesApp/App/CommandDispatcher.swift` |
| Presentation and saved results | `SkillPresentation`, `SessionRecord`, and the shared session UI |

## Implement the workflow

1. Define the input, output, required permissions, cancellation behavior, and recovery behavior.
   Decide whether it needs a target window or an audio session. New capture must correspond to an
   explicit user action; hovering is not permission to begin recording.
2. Add a stable `CompanionSkillKind` case with its labels, symbol, event, and capabilities. Preserve old
   persisted cases. Add it to `radialSkills` only if it belongs in the wheel, and verify the wheel's
   layout and hit targets with the new count.
3. Implement `ActiveSkillSession`: `start`, `tick`, `finish`, and `cancel`. Use `SkillTickContext` and
   `SkillFinalizeContext`. `finish` returns a `SkillCompletionOutcome` with the saved content;
   cancellation stops owned work and prevents late callbacks from publishing stale results.
4. Construct the session in `SkillCoordinator.makeSession`. This is currently an explicit factory
   switch, not an automatic plugin registry. Reuse the coordinator's lifetime and completion handling.
   Use `SnapSkillSession` and `AudioSkillSession` as examples, keeping their processing services separate.
5. Add the command mapping through `AppCommand` and `CommandDispatcher` so menus, hotkeys, and the wheel
   reach one workflow. Target the intended foreground window through the existing targeting service.
6. Reuse the session header, controls, transcript viewport, failure notice, and HUD components. Put
   state in a presentation model and send actions to its owner. Add pack-authored reactions to the new
   skill event instead of branching on character IDs.
7. Store results through the existing Vault path. For new persisted fields, preserve backward decoding
   and update search/export only where the feature requires it. Keep partial content recoverable.

The lifecycle protocol runs on the main actor to coordinate UI state; it does not authorize heavy work
there. Capture, encoding, OCR, inference, and file access belong to workers. Reuse speech and text
providers, permission recovery, the command dispatcher, and resource priority instead of duplicating them.

## Check it

Run `make check BUILD_DIR=/tmp/sillies-check`. Add focused coverage for permissions, finish/cancel,
late results, window disappearance, partial failure, persistence, and recovery. Audio changes also run
`make stress`; concurrency changes run `make race-check`.

Exercise the actual menu/hotkey/wheel entry, minimum window size, keyboard selection/copy, scrolling,
and window layering. Capture workflows need a short, consented live check in addition to model tests.

Read [existing skill behavior](../skills.md), [commands and architecture](../architecture.md), and
[development checks](../development.md). Start with [the development contract](../../AGENTS.md).
