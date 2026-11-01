# Add a color theme

Add one JSON file to [`Sources/SilliesDesign/Themes`](../../Sources/SilliesDesign/Themes).
Sillies discovers it automatically and shows a preview in **Settings → Appearance**. Palettes contain
data only. They cannot load code, images, fonts, or network resources.

## Start from a complete palette

Copy an existing file, then change its stable `id`, filename, display `name`, explanatory `comment`,
and `order`. The filename must equal the ID, for example `ocean.json` with `"id": "ocean"`.
Keep `"version": 1`. IDs use lowercase letters, digits, and hyphens; names are at most 40 characters.

Every palette supplies both `light` and `dark`. Appearance (System, Light, Dark) is independent of the
selected theme. Fill all these semantic roles with opaque `#RRGGBB` colors:

| Role | Used for |
| --- | --- |
| `paper`, `card`, `soft` | Window, card, and inset surfaces |
| `ink`, `secondary` | Primary and secondary text |
| `border` | Separators and outlines |
| `accent` | Links, icons, and accent text |
| `accentFill`, `onAccent` | Prominent buttons and outgoing chat bubbles |
| `selection`, `onSelection` | Native text selection |
| `success`, `warning`, `danger` | Semantic status colors |

The loader requires 4.5:1 contrast for text, accent text, and status colors on the three surfaces, for `onAccent` on
`accentFill`, and for `onSelection` on `selection`. Match the whole interface rather than changing only
the window background. Native Increase Contrast uses macOS semantic colors.

## Keep rendering predictable

`SilliesDesign` validates bounded JSON on a worker. `AppearancePreferences` owns saved choices, and
`SilliesTheme` exposes semantic colors to presentation. Native editors and window backgrounds share
those colors. Changes must preserve selection, drafts, and transcript reading position. Character
artwork retains its own colors; a palette is not a character repaint.

Use `SilliesTheme` roles for new UI and `AccentButtonStyle` for prominent actions. Avoid fixed white
text on a theme accent: a dark palette may need dark text on its bright accent. Do not reload a theme
from disk during rendering, animate the whole desktop, or add a per-window theme timer.

The initial in-memory Sillies fallback is generated from `sillies.json`. If changing that palette, run:

```sh
python3 scripts/theme-fallback.py
```

Theme names are proper palette names and are displayed exactly as contributed. A new palette needs
only its JSON file; it does not require changes to Swift or to the language catalogs.

```sh
source scripts/toolchain.sh
SILLIES_SKILL_UI_SNAPSHOTS=1 swift test --no-parallel --filter everyBundledTheme
make check BUILD_DIR=/tmp/sillies-theme
```

Review both appearances in Chat, Settings, the Vault, text selection, inactive windows, and the skill
wheel. Snapshot tests write previews into the macOS temporary directory. Include screenshots and the
palette's attribution/license when opening the pull request.
