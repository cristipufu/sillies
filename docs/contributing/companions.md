# Add a companion

Start with a personality using existing artwork, or bring a new character to life. A companion is a
JSON pack plus a registered renderer and animation clips. Packs are bundled with the app; there is no
runtime executable-plugin loader.

## Start here

| Concern | Location |
| --- | --- |
| Names, personality, reactions, scene preferences | `Sources/SilliesApp/Resources/Characters/` |
| Pack schema and validation | `Sources/SilliesCore/CharacterDefinition.swift` |
| Artwork factories | `Sources/SilliesApp/Rendering/RendererRegistry.swift` |
| Animation registration | `Sources/SilliesApp/Rendering/AnimationLibrary.swift` |

## Add the pack

1. Copy a small existing character JSON and give it a unique, stable `id`, `name`, `subtitle`, and `bio`.
   Set its `order` for the crew picker. Preserve existing IDs when updating a character.
2. Start with an existing renderer such as `cat`, `frog`, or `robot`. Write reactions in the pack:
   event, animation, duration, priority, cooldown, and selection weight. Always include an ambient
   reaction, and provide side-hanging reactions and responses to the current skill events.
3. Add `playful` preferences if the character should join scenes. Those preferences choose scenes,
   character-specific clips, and signs; they do not change window tracking.
4. For original artwork, subclass `CharacterRig` and register its factory in `RendererRegistry`.
   Keep the named limbs, head, eyes, and attachment anchors compatible with shared clips. Put unique
   clips in their own animation file and register them in `AnimationLibrary`.
5. Give every animation a reset path and a reduced-motion expression. Reuse layers and the existing
   clocks; do not add timers to a character.

The catalog discovers bundled packs automatically, and the crew picker reads the catalog. No
character-specific branch belongs in the controller, behavior engine, or window tracker.

## Check it

Run `make check BUILD_DIR=/tmp/sillies-check`. Export the actual character artwork:

```sh
/tmp/sillies-check/Sillies.app/Contents/MacOS/Sillies --snapshot-dir build/character-previews
```

Inspect top and both side poses, pickup, resize, skill reactions, scene cancellation, and Reduce Motion.
Verify that transparent areas pass input through and that artwork stays outside the document.

The [renderer and attachment contract](../extending.md#add-a-character) covers design coordinates,
limb depth, hit testing, transitions, and example rigs. For new behavior, continue with
[interactions](interactions.md). Follow the [development contract](../../AGENTS.md).
