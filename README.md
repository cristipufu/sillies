# Sillies

Little companions. Big personalities.

A native macOS menu-bar app. **Mochi** the sleepy ginger cat, **Kiko** the dramatic ninja, **Pogo** the curious frog, and **Bolt** the earnest robot roam your window edges and react to your workspace. Swift 6, AppKit, SwiftUI, Core Animation.

## Run

Requires macOS 26+, Swift 6+, and Xcode 26 or later for the test suite. Build scripts use an installed `/Applications/Xcode.app` when Command Line Tools are selected; they do not change your global developer settings.

```sh
make run
```

The app is built at `build/Sillies.app`. Its paw icon appears in the menu bar. Mochi and Kiko start enabled, in Playful mode, following window edges. Choose any combination of the twelve characters in the crew picker; saved selections are preserved across updates. The popover stays compact (at most 640 points tall) and scrolls to the remaining controls. The app does not appear in the Dock.

Pogo waddles, hops, grips sides with sticky fingertips, and slips beneath fixed hands before pulling back up. Bolt takes measured steps, adjusts telescoping legs during resizing, climbs with magnetic mittens, and turns its face into a viewfinder for Snap. Each character has its own reaction pack and animation overrides, including reduced-motion expressions.

The crew also includes **Boo** the bashful ghost, **Bloop** the affectionate octopus, **Sprout** the mushroom gardener, **Pip** the delighted axolotl, **Pebble** the dignified penguin, **Taro** the baby dragon, **Nib** the cautious hedgehog, and **Mallow** the floppy-eared bunny. Each has distinct vector artwork, signature actions, side-hanging clips, and all five radial skills. Your existing crew selection stays saved; new companions are available in the scrolling picker.

Choose **Listen** to record and transcribe both sides of a meeting with local speaker echo cancellation, **Participate** for the same capture plus suggestions in your companion’s speech bubble, **Snap** for a screenshot copied to the clipboard, **Explain** for OCR with a local explanation, or **Record** for playable microphone audio with a transcript and notes. Right-click a companion for the same actions and **Save Clipboard**. Settings → Everyday Shortcuts offers configurable global shortcuts for every skill, Save Clipboard, the Vault, and pause/resume, plus optional launch at login. Window shortcuts resolve the foreground window when invoked and cancel if focus changes during lookup. The Vault also has **Add text / link** and audio playback. [Skill behavior and local processing requirements](docs/skills.md).

Dictate into a focused text field with **Control–Option–Space** (hold) or **Control–Option–D** (toggle). Both are configurable. Choose verbatim or lightly cleaned output and add names, Romanian spellings, and technical terms to the personal dictionary. Insertion requires Accessibility; copy-only dictation does not. Text that cannot be safely inserted stays in **Writing recovery**, independently of meeting retention. Selection commands offer shortening, grammar correction, and translation using the selected local writing model. Settings → **Local AI** offers optional Qwen3.5 4B, Qwen3.5 9B, Gemma 4 E4B, and Ministral 3 8B downloads alongside Apple Intelligence. [Local text models and contributor guide](docs/local-text-models.md).

Snap images become searchable through background OCR. The Vault has indexed full-text search, speaker renaming, protection from automatic trimming, Markdown export with attachments, and paste-back. **Search Pocket Stash** opens a keyboard picker for saved text. Captures are kept until explicitly deleted by default; Settings in the Vault lets you choose a retention limit. See [everyday writing and retrieval](docs/everyday-workflows.md) for behavior, privacy, and failure recovery.



- **Window edges, by default:** companions walk above the focused window, ride its movement, brace/scramble during resizing, and squash/settle when it stops. Independent window movement confirms a drag before display-linked pointer attachment begins. Basic tracking works without Accessibility or Screen Recording permission.
- **Room for everyone:** companions can pass each other while walking, but reserve separate stopping spots. They still wave when they meet; a crowded edge lets excess companions wait for room.
- **Tall windows:** companions hang from exterior sides by their hands, with upright bodies, dangling feet, and occasional climbs up and down. Fully screen-filling windows have no exterior seat, so the crew waits.
- **Desktop:** an explicit placement option in the menu-bar popover; it is never a silent permission fallback.
- **Optional Accessibility:** adds faster focus/context notifications for applications that expose them.
- **Play with the crew:** click a character to greet it or drag its body to pick it up. Enabling Play closes the popover. Transparent space and window manipulation controls keep passing input through; background document content does not disable the characters.
- **Pause:** hides companions and stops their animation, motion clock, decision scheduler, and active-window observation.
- **Settings:** window following, reduced motion, per-app exclusions, permission status, and a small diagnostics panel.

Open **Give them a window to play on** from the menu-bar popover for a real native playground. Drag or resize it yourself, or try Squeeze, Nudge, and Make it tall. Window following needs no permission setup. Optional enhanced app reactions are available in Settings; development signing can require re-enabling that optional permission after a rebuild.

## Develop

```sh
make debug       # Debug .app bundle
make preview     # Open the control center in a regular preview window
make test        # Pure behavior, geometry, and pack validation tests
make check       # Formatting, tests, debug bundle, catalog, native Settings/Vault lifecycle
make gui-check   # Also checks lifecycle, window tracking, and live drag attachment
make build       # Optimized local build
```

Open `Package.swift` in Xcode to browse and debug. Use the bundled app for permission testing, rather than running the bare executable from SwiftPM.

```sh
build/Sillies.app/Contents/MacOS/Sillies --snapshot-dir build/previews
```

Exports the control center and all twelve character portraits as PNGs, then exits. This renders Sillies' own views; it does not capture other apps.

## Structure

```text
Sources/
  SilliesCore/                 Platform-independent decisions and geometry
    BehaviorEngine.swift       Priority, cooldown, weighted personality, deadlines
    CharacterDefinition.swift Validated, versioned character-pack schema
    Identifiers.swift          Open event and animation identifiers
    Motion.swift               Frame-independent movement and safe surfaces
    AttachmentPose.swift       Standing feet and upright side handholds
    PointerWindowGesture.swift Immediate pointer mapping and metadata validation
    WindowDragSession.swift    Movement confirmation and bounded drag fallback
    CharacterTransitions.swift Optional entry/exit/reattachment profiles
  SilliesApp/
    App/                       Lifecycle, catalog, settings, companion coordination
    Platform/                  Workspace notifications and isolated AX observation
    Rendering/                 Small panels, vector rigs, registered animation clips
    UI/                        Menu-bar control center and settings
    Resources/Characters/      Twelve independent character behavior definitions
Tests/                         Deterministic logic and animation extension tests
```

See [architecture](docs/architecture.md), [adding characters and reactions](docs/extending.md), and [performance](docs/performance.md).

## Current boundaries

This is the first local implementation, not a notarized release. Tab/context reactions depend on the notifications an application exposes; Sillies does not claim to detect every tab switch or understand document contents. The live-window check opens a native window, validates its actual WindowServer ID, resizes and moves it, checks the exterior sides, and closes it. This is a GUI test and requires a logged-in macOS desktop. It exports Sillies-owned view composites to `build/previews/window-top.png` and `window-sides.png`; other apps are not captured.

Terminal build completion, typing reactions, browser extensions, imported sprite packs, and automatic updates are not implemented yet.

Display geometry supports screens above/left of the primary display. Fullscreen, Stage Manager, Mission Control, and Accessibility behavior should be exercised on the intended OS versions and display setups before shipping. Core tests cover coordinate conversion; they do not substitute for that interactive matrix.
