# Add an interaction

An interaction can be a wave after an app switch, a new animation, a two-companion scene, or a response
to a new workspace event. Choose the smallest extension that expresses the behavior.

| What you want | What to change |
| --- | --- |
| A different response to a known event | A character's JSON reactions |
| A new movement or expression | A registered animation clip, then a JSON reaction |
| A solo or shared playful scene | Scene choreography, participating packs, and any new clips or props |
| A response to a new system signal | An event producer, then independent pack reactions |

## React to an existing event

Add a reaction in `Sources/SilliesApp/Resources/Characters/<character>.json`. For example, this uses
the existing app-switch event and wave animation:

```json
{
  "id": "hello-new-window",
  "event": "appChanged",
  "animation": "wave",
  "duration": 1.8,
  "priority": 2,
  "cooldown": 8,
  "weight": 1,
  "motion": "none"
}
```

The engine selects the highest eligible priority, then makes a weighted choice among ties. Durations
and cooldowns use monotonic seconds. Character choices stay in JSON, without controller conditionals.

## Add an animation

Register a named clip in `AnimationLibrary`, either shared or scoped to a character. Keep artwork in
the rig and animation code in its own file. Reuse named layers, provide reset/cancellation behavior,
and register a static reduced-motion expression. Check hanging poses as well as standing poses.

Follow the [animation recipe](../extending.md#add-an-animation) for registration examples and pose
variants. A new clip does not need changes to window observation or a private timer.

## Choreograph a playful scene

1. Add a scene to `Sources/SilliesApp/Resources/Scenes/playful-scenes.json`, with a stable ID, trigger,
   layout, cooldown, and finite phases. Start with an existing scene that uses similar travel.
2. Define lead/partner cues with existing animation IDs and destinations. Finish at `home` and use
   validated exterior routes for climbing or leaving the edge. Use phase motion for shared travel.
3. Opt characters into the scene through their pack's `playful.scenes`; use `playful.clips` for
   character-specific performances and pack-authored signs for personality.
4. If new artwork is necessary, keep it in the renderer. Props and hand grips must share geometry and
   motion so they remain connected. A new route or prop kind needs corresponding schema, validation,
   geometry, and renderer support; inventing a JSON string alone is insufficient.

`PlayfulSceneDirector` selects scenes, `PlayfulSceneLayout` plans geometry, and `PlayfulSceneSession`
advances phases. `PlayfulSceneCoordinator` applies those plans through existing clocks. Never put
character or scene IDs into window tracking. Busy companions must remain available for their skill;
pickup, window manipulation, pause, exclusions, and shutdown interrupt scenes.

The [scene contract](../extending.md#playful-scenes) specifies phases, shared motion, corner transitions,
props, and input isolation.

## Introduce a workspace event

Use a namespaced `EventKind` and a `WorkspaceEventProducer` that emits bounded, throttled events with
monotonic timestamps. Wire it through the app's `CompanionServices.eventProducers`, then add reactions
in packs. Keep platform observation separate from behavior selection and stop the producer on pause,
exclusion, and termination. Accessibility and window-metadata reads stay on the existing isolated
platform worker; an event producer must not block the main actor on another app.

New capture, network access, or collection of keyboard content requires an explicit product requirement.
See [event sources](../extending.md#add-an-event-source) and [the privacy contract](../../AGENTS.md).

## Check it

Run `make check BUILD_DIR=/tmp/sillies-check`. Scene changes also need the `playful` test cases and a
visual check of actual movement, cancellation, and reduced motion:

```sh
bash scripts/test.sh --filter playful
/tmp/sillies-check/Sillies.app/Contents/MacOS/Sillies --playful-scene dance --without-accessibility
```

Replace `dance` with your scene ID. The preview uses temporary settings and exits automatically.
Tests advance complete scenes in virtual time; they do not require a multi-hour recording. For
sequential GUI previews and frame exports, see the [scene guide](../extending.md#playful-scenes).
