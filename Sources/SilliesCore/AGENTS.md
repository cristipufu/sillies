# Core domain models

Keep behavior, geometry, timing decisions, transcript indexing, and transition policies here as deterministic value models. No AppKit, timers, device access, file I/O, or app/audio/persistence imports. Pass monotonic time into decisions; never read a clock internally. Keep character responses in pack data and saved IDs stable.

Example: window-transition settlement is evaluated by `WindowTransitionEvaluation` with `WindowTransitionObservation` and an explicit timestamp. The platform applies its decision and owns scheduling. A discovery request during manipulation resolves to `.trackedWindow` regardless of older queued requests.

Put new pure behavior tests in `Tests/SilliesCoreTests`. Test semantic outcomes and boundaries, including reordered observations and virtual-time deadlines. Avoid testing private method names or file length. Run `make check` when a change affects native behavior or geometry as well as its targeted Core tests.

`SessionFailure` owns typed failure categories and recovery actions. Never infer permission state from session summaries or localized messages. `SessionRecord+Codable` preserves legacy keys; historical error matching is confined to that decoding boundary.

Construct sessions with `SessionOrigin`, `SessionContent`, and `SessionMetadata`; keep their cohesive groups instead of extending a flat argument list. Markdown output belongs to `SessionMarkdownFormatter`. Unknown saved failure identifiers must round-trip unchanged while exposing no unsupported recovery action. Invalid required JSON fields must continue to throw.
