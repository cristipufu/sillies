# Sillies

Little companions. Big personalities.

A native macOS menu-bar app. **Mochi**, a sleepy ginger cat, and **Kiko**, an earnest little ninja, roam your window edges and react to your workspace. Swift 6, AppKit, SwiftUI, Core Animation. No third-party dependencies or network services.

## Run

Requires macOS 14+, Swift 6+, and Xcode for the test suite. Build scripts use an installed `/Applications/Xcode.app` when Command Line Tools are selected; they do not change your global developer settings.

```sh
make run
```

The app is built at `build/Sillies.app`. Its paw icon appears in the menu bar. Both companions start enabled, in Playful mode, following window edges. The app does not appear in the Dock.

- **Window edges, by default:** companions walk above the focused window, ride its movement, brace/scramble during resizing, and squash/settle when it stops. Independent window movement confirms a drag before display-linked pointer attachment begins. Basic tracking works without Accessibility or Screen Recording permission.
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
make check       # Tests, bundle, lifecycle, real window tracking and live drag regression
make build       # Optimized local build
```

Open `Package.swift` in Xcode to browse and debug. Use the bundled app for permission testing, rather than running the bare executable from SwiftPM.

```sh
build/Sillies.app/Contents/MacOS/Sillies --snapshot-dir build/previews
```

Exports the control center and both character portraits as PNGs, then exits. This renders Sillies' own views; it does not capture other apps.

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
    Resources/Characters/      Mochi and Kiko's behavior definitions
Tests/                         Deterministic logic and animation extension tests
```

See [architecture](docs/architecture.md), [adding characters and reactions](docs/extending.md), and [performance](docs/performance.md).

## Current boundaries

This is the first local implementation, not a notarized release. Tab/context reactions depend on the notifications an application exposes; Sillies does not claim to detect every tab switch or understand document contents. The live-window check opens a native window, validates its actual WindowServer ID, resizes and moves it, checks the exterior sides, and closes it. This is a GUI test and requires a logged-in macOS desktop. It exports Sillies-owned view composites to `build/previews/window-top.png` and `window-sides.png`; other apps are not captured.

Terminal build completion, typing reactions, browser extensions, launch at login, imported sprite packs, and automatic updates are not implemented yet.

Display geometry supports screens above/left of the primary display. Fullscreen, Stage Manager, Mission Control, and Accessibility behavior should be exercised on the intended OS versions and display setups before shipping. Core tests cover coordinate conversion; they do not substitute for that interactive matrix.
