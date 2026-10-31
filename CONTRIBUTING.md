# Contributing to Sillies

Bug reports, thoughtful UX improvements, artwork, interactions, skills, and local model integrations
are welcome. Sillies should feel playful while remaining dependable when it handles someone's work.

Found a vulnerability? Use the private route in [SECURITY.md](SECURITY.md), not a public bug report.

## Report a bug or suggest an idea

[Open an issue](https://github.com/cristipufu/sillies/issues/new) with what you tried, what you expected,
and what happened. For a bug, include the app version or commit, macOS version, and Mac chip/memory.

Include details relevant to the workflow:

- **Movement or artwork:** companion, Playful/Calm mode, window edge, target app, display setup, and Reduce Motion.
- **Audio or notes:** skill, speech/text model and revision, spoken language, speaker detection, approximate
  session length, and whether you used speakers or headphones.
- **Dictation or insertion:** hold/toggle mode, destination app, permission status, and whether focus changed.
- **Crashes or failures:** the exact message and a redacted diagnostic excerpt, if available.

Use sample text and consenting test audio. Public issues, screenshots, logs, and crash reports can reveal
window titles, paths, meeting content, or names. Share only what is needed. Do not attach your entire Vault.

For an idea, describe the user's task and the expected interaction. A small sketch or sample scene helps.

## Choose an extension

| Contribution | Guide |
| --- | --- |
| Companion or personality | [Character packs and artwork](docs/contributing/companions.md) |
| Reaction, animation, or shared scene | [Interactions](docs/contributing/interactions.md) |
| A new activity | [Skills](docs/contributing/skills.md) |
| Speech recognition model or runtime | [STT providers](docs/contributing/speech-models.md) |
| Text generation model or runtime | [Text / LLM providers](docs/contributing/text-models.md) |

These are source contributions. JSON can reuse existing renderers and clips; executable plugins are not
loaded from downloads. If a change adds a permission, data collection, or a network service, discuss the
product requirement first. Existing dictation does not authorize background keystroke or clipboard collection.

## Set up locally

Use an Apple silicon Mac with macOS 26+, Xcode 26+ with Swift 6.2 or later, and Xcode's Metal toolchain.
If needed, install the latter with `xcodebuild -downloadComponent MetalToolchain`.

```sh
make debug BUILD_DIR=/tmp/sillies-development
open /tmp/sillies-development/Sillies.app
```

The repository scripts select Xcode locally when necessary; they do not change global `xcode-select`.
Use the bundled app for permission testing. Read [AGENTS.md](AGENTS.md), the ownership instructions beside
the module you change, and [the development guide](docs/development.md).

## Keep the foundation sound

- Follow Robert C. Martin's Clean Code principles: focused functions and files, clear names, encapsulated
  state transitions, cohesive context types, explicit errors, and one owner for each responsibility.
- Keep behavior and geometry in `SilliesCore`; character decisions belong in packs. Keep event producers,
  animation, capture, inference, storage, and presentation separate.
- Keep blocking I/O, Accessibility queries, audio processing, and model work off the main actor. Bound queues
  and memory. Every producer needs cancellation and teardown on pause, exclusion, and shutdown.
- Reuse Sillies' window, typography, color, control, permission, and recovery patterns. Preserve text selection,
  scroll position, input pass-through, and window layering. Inspect light/dark and reduced-motion states.
- Preserve saved IDs, preference keys, and old Vault decoding. Keep failed operations recoverable and never
  acknowledge a save that failed.
- Keep attribution with any imported code, artwork, or model. Update [third-party notices](THIRD_PARTY_NOTICES.md)
  and [the privacy policy](PRIVACY.md) when the relevant behavior changes.

## Verify the change

```sh
swift format format --in-place path/to/ChangedFile.swift
bash scripts/test.sh --filter RelevantTest
make check BUILD_DIR=/tmp/sillies-check
```

Run `make check` for behavior/platform changes. Audio/transcript/lifecycle changes also need relevant
`make stress` coverage; concurrency changes need `make race-check`. Scene changes need a short visual
check of movement as well as deterministic tests. Crash fixes need the failing-input regression and the
real triggering workflow; Settings/menu/window changes need the native lifecycle check included in `make check`.

Use focused tests for observable behavior, failure, cancellation, and recovery. Do not add tests that merely
repeat the implementation. Bounded, accelerated workloads replace multi-hour tests. Routine checks do not
download model weights or require private meeting recordings. Real-model evaluations are separate opt-in runs.

Documentation-only changes need valid links and a visual review where relevant. The [README preview procedure](docs/development.md#readme-artwork)
renders native app components with sample data, without capturing your desktop.

## Send a pull request

Keep the change focused and use a commit title that describes the resulting behavior. Explain the problem,
what changes for the user, the checks you ran, and any remaining limitations. Include before/after images
or a short clip for visible changes, using sample content.

State which checks were not run and why. The existing CI/release workflows depend on their configured
toolchain and signing credentials; their presence is not proof that a change has passed validation.

## License

By submitting a contribution, you agree to license your original contribution under Sillies'
[MIT License](LICENSE). Contribute only material you have the right to share. Imported material keeps
its original notices and terms; model weights are not automatically covered by the app's license.
