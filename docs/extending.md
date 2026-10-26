# Extending Sillies

## Add a reaction

Edit a character's JSON in `Sources/SilliesApp/Resources/Characters`. Reuse an existing event and animation without changing Swift code:

```json
{
  "id": "a-little-wave",
  "event": "appChanged",
  "animation": "wave",
  "duration": 1.8,
  "priority": 2,
  "cooldown": 8,
  "weight": 1,
  "motion": "none"
}
```

`duration` and `cooldown` are seconds of monotonic time. Lower priority reactions cannot interrupt higher priority active states. Among eligible reactions for an event, the engine first selects the highest priority, then performs a weighted draw. Use equal priorities for alternatives. `motion` is `none`, `stroll`, or `hop`.

Ambient durations are longer in Calm mode. Immediate event reaction durations stay unchanged. Always include an ambient reaction; unknown schema versions, duplicate IDs, invalid numbers, missing renderers, and missing animation clips fail validation before panels appear.

Use `ambient.wall` for side-specific choices. All bundled characters define `hang` with no travel and `climb` with `motion: "stroll"`. The same normalized movement path runs vertically on sides. Packs without wall overrides keep their normal ambient choices; the renderer adapts standing walk/idle/manipulation clips to climbing, hanging, or catching the edge. No character-specific controller branch is needed.

## Stopping spots and greetings

`PerchSpacing` reserves distinct resting positions along horizontal or vertical surfaces. Walking companions reserve their destination; carried companions reserve their pickup slot so a return stays clear. `StrollPlan` may cross another companion's path, but its endpoint must be free. Interruptions and completed movements also check the nearest available resting spot. Neighbor greetings start just outside the resting gap, preserving each pack's existing wave/happy reactions and cooldowns.

The controller reuses its shared movement clock for brief spacing adjustments. If an edge has insufficient room, excess companions wait hidden with their animations stopped; behavior deadlines and placement changes retry when room becomes available. Geometry changes resolve spacing synchronously without delaying window attachment. No character-specific logic, timers, or per-frame SwiftUI updates are needed.

## Add a character

1. Add a version-1 JSON file with a unique character ID.
2. Reuse `cat`, `ninja`, `frog`, or `robot` to prototype a personality with existing artwork.
3. For new artwork, subclass `CharacterRig` and register its factory in `RendererRegistry`.
4. Use the rig's named head, arms, feet, eyes, and accessory layers so shared clips work automatically.
5. Run `make check` and inspect `--snapshot-dir` exports.

The catalog reads bundled JSON files and sorts them by optional `"order"` (then ID). The control center enumerates that catalog automatically in a wrapping two-column grid. No character-specific conditionals belong in the behavior engine or window tracker. Rigs use a 128×128 design coordinate system. Standing feet attach at `(64, 20)`; side poses attach by the upper hand at `(112, 101)` on the left or `(16, 101)` on the right. Runtime panels use a small 256-unit canvas for animation overshoot; portraits remain compact. Side artwork stays upright, with raised arms and dangling feet. Draw torso and clothing shapes on `rig.torso` so limbs (`leftFoot`, `rightFoot`, `leftArm`, `rightArm`) and `head` layer above the body automatically. Pass custom `gripFill`, `sleeveFill`, and `gripOutline` hex colors to `super.init(gripFill:sleeveFill:gripOutline:)` for new artwork, or supply equivalent hand geometry at these anchors. Panel placement, body pivots, and world clipping use `AttachmentPose`, so changing that contract requires updating all three. `workspaceMotion` holds continuous inertia separately from the animation clip; hanging grips sit outside that body transform to preserve contact. `windowSettled` supplies the landing or grip catch after manipulation; it must remain interruptible by a new movement or resize.

The first implementation intentionally bundles trusted packs. Runtime downloads and user-provided executable code are not part of the loading model. A future sprite renderer can register against the same IDs and return an equivalent renderable rig; an atlas-backed CALayer can replace vector parts without changing event producers.

`CompanionWindowLayout` crops attached native panels to the exterior of the focused window. Artwork still uses the same design anchors, but the local panel contact is no longer necessarily its center. Keep both rig and transition pivots at `contactOffset`; never restore a full square native input window over the title bar to create animation overshoot. Pickup can use the full canvas, and release restores the crop.

## Add an animation

Register an open animation ID and a clip in `AnimationLibrary`. Shared built-in definitions live in `BuiltinAnimations.swift`; character-specific clips can live beside their artwork. A clip receives a rig and adds Core Animation animations to its named parts. `resetBehaviorPose()` removes old behavior clips before every behavior change while preserving window inertia. Clips must set any persistent expression they need; add resets for new persistent properties there. Full `resetPose()` also clears workspace feedback when hiding/stopping. The outer presentation layer is independent, so behavior changes preserve entry/exit transitions.

```swift
animations.register("victoryDance", characterID: "your-character") { rig in
  // Add cancellable Core Animation clips to named rig parts.
}
animations.registerReducedMotion("victoryDance", characterID: "your-character") { rig in
  rig.delight.opacity = 1
}
animations.registerVariant(.walk, pose: .hangingLeft, clip: .climb)
```

Omit `characterID` for a shared clip, and optionally call `registerReducedMotion` when the animation has a static expression under Reduce Motion. Pose variants resolve first, then a character override takes precedence over the shared clip. Register both hanging poses when a variant should apply to both sides. Supply customized libraries to `CompanionController` before its catalog validation; no change to window tracking or behavior selection is required.

Open identifiers accept custom strings, so character packs are not constrained by a closed animation enum. Add a static convenience constant to `AnimationID` when the animation is shared. Keep animations cancellable, honor reduced motion, and avoid per-frame allocation or timers inside clips.

### Bundled character examples

`FrogRig` and `FrogAnimations` implement Pogo; `RobotRig` and `RobotAnimations` implement Bolt. Register each character's clips in `AnimationLibrary.init()` after shared clips. `RigAnimation` supplies reusable layer keyframes and oscillations; clips reuse existing layers and introduce no timers. Reaction choices remain in `pogo.json` and `bolt.json`.

Pogo overrides shared walk/climb/catch clips and uses namespaced `pogo.hop` and `pogo.pocket` clips. Bolt overrides walk/resize/climb clips and uses `bolt.scan` for its viewfinder in standing and hanging poses. Custom IDs need pose variants when their standing animation would be inappropriate on a side (see Pogo's hop registration).

For extra animated layers, keep reset responsibility in the rig: `RobotRig.resetBehaviorPose()` calls `super`, removes antenna/viewfinder animations, and restores the face. Override that method instead of adding character checks to the base rig or controller. Supply static reduced-motion expressions for custom IDs. Existing saved crew selections stay unchanged when new packs are installed; the picker discovers every pack, and automated GUI runs explicitly exercise the entire catalog.

## Change entry, exit, or reattachment

Add an optional `transitions` object to a version-1 character JSON:

```json
"transitions": {
  "enter": { "animation": "appear", "duration": 0.3 },
  "exit": { "animation": "disappear", "duration": 0.18 },
  "reattach": { "animation": "fade", "duration": 0.16 }
}
```

Built-ins are `appear` (fade/pop), `disappear` (fade/shrink), and `fade`. Missing entry/exit values use defaults; missing reattachment inherits entry. Older packs need no migration. Durations must be finite and between 0.05 and 2 seconds.

For a new effect, register a finite clip in `TransitionLibrary`. The closure receives the transition kind, requested duration, and current presented opacity/scale, and returns a `CAAnimation`. Use those starting values when possible so an interrupted exit can reverse smoothly. Set the returned animation's duration; grouped child animations also need appropriate durations. The library owns the clip; `CompanionPresentation` owns visibility and completion, including cancellation and reduced motion. Never order a panel or install a timer inside a clip.

Exits run when an attachment disappears. Pause, exclusions, character removal, unsafe placement, and quitting hide immediately. A new attachment cancels an in-flight exit, and stale completion callbacks cannot hide the returned character. Behavior reactions and geometry remain responsive during transitions.

## Preserve native window interaction

Play mode enables input over filled character artwork, including when it is above background document content. Native alpha hit testing passes transparent canvas through and allows the first click without waiting for hover registration. The focused document and resize strip remain protected. Native hit testing beneath the artwork also reserves headers and resize borders of inactive windows. New rigs should put interactive filled shapes in the named stage or hanging-arms hierarchy; decorative dust, shadows, and text do not create valid pickup targets.

Run the opt-in `--external-drag-test --without-accessibility` check for a custom main-header drag through `NSWindow.performDrag`, plus top/corner resizing under the panels with Play mode enabled. Add `--expect-stationary` to exercise a non-draggable main header: neither the characters nor the clipping geometry may move. Both use disposable fixtures. Normal startup never posts mouse input.

`--interaction-test --without-accessibility` posts actual clicks, a 62×28-point pickup drag, and release to Sillies-owned windows. It verifies that disabled Play passes clicks through, that enabled Play works over background document content without a preceding hover, and that returning from an unavailable surface leaves distinct character slots. Event-posting access must already exist; the check skips without prompting otherwise. It restores the pointer and focus and is excluded from default `make check`.

## Add an event source

1. Define a namespaced `EventKind`, such as `terminal.buildFinished`.
2. Implement a `@MainActor` type conforming to `WorkspaceEventProducer` in `Platform/`, or an optional integration module.
3. Convert raw signals to `WorkspaceEvent` values using monotonic timestamps.
4. Throttle noisy sources before routing them to the controller, and pass the producer to `CompanionController(settings:eventProducers:)`.
5. Add independent character reactions in JSON.

For semantic events like successful terminal commands, prefer an explicit local integration over repeatedly reading the screen. Producers must have start/stop lifetimes and must stop active work when companions are paused or excluded.

## Drop-to-bind companion skills

`DropReturnPlan` chooses a short accelerating fall for an unassigned release at or above the pickup height. A release below the pickup height, or any explicit radial skill selection, uses an exit/entry pair instead. Returns use the saved normalized pickup slot, never the release point's projected slot. `CompanionDropReturn` owns cancellable arrival work, uses the shared movement clock for falls, and delegates disappearance to `CompanionPresentation`. Landing reactions and skill activation happen on arrival. Pause, removal, or loss of a safe perch cancel pending arrival work; Reduce Motion returns immediately.

An unselected skill bar stays beside the original perch, even when its candidate task targets another window. Only a selected skill changes that attachment. Run `--drop-return-test --without-accessibility` to exercise real above/below drops, a radial menu dismissed without a choice, and an explicitly selected Focus skill against Sillies-owned windows. Like `--interaction-test`, it requires existing event-posting access and never prompts for it.

Companions support spatial window-binding skills coordinated by `SkillCoordinator` and persisted locally by `SessionVaultStore`:

- **Events**: `skill.snap`, `skill.listen`, `skill.watch`, `skill.focus`, `skill.completed`, and `skill.stash`.
- **Shared animations**: `snap`, `listen`, `watch`, and `focus` (with reduced-motion expressions and side-hanging pose variants).
- **Radial Skill Menu**: `RadialSkillMenuLayout` computes deterministic upward/downward bubble positions and hit-testing in `SilliesCore`.
- **Session Vault**: `SessionRecord` and `SessionSummarizer` live in `SilliesCore`; `WindowSnapshotService` (`ScreenCaptureKit` + `Vision`) and `AudioTranscriptionService` (`ScreenCaptureKit` + `Speech`) run strictly on-device when initiated by user drop gestures.
