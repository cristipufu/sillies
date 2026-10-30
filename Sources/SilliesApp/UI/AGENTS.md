# Native and SwiftUI presentation

Views render presentation models and forward commands to their owner. Do not perform synchronous file/image loading, audio processing, or AX/window-list queries here. Keep transcript rendering in its native viewport with incremental updates. Reading/selection must remain stable; following resumes on Jump to latest or returning to the bottom. Coalesce audio progress through `AudioSessionUpdateDelivery`, preserving lifecycle event order.

Keep header, finish controls, transcript viewport, and footer visible at minimum size. Put overflowing short controls in their own scroll area; never wrap the live transcript in `ViewThatFits` or a second scrolling container. Suggestion bubbles measure text when content/available width changes and preserve native z-order and input pass-through during movement.

Example: a new transcript status is a presentation-model property, not view-level string matching. A vault action belongs in `SessionVaultModel`; a view invokes it instead of editing stores directly.

Run `LiveTranscriptTests`, `SkillInterfaceTests`, `MeetingSpeechBubbleTests`, `SessionVaultModelTests`, `make stress`, and `make check` as relevant. Use the opt-in UI snapshots for visual changes and inspect minimum-size, reading/selection, failure, and long-text states.

Live and saved session errors use `SessionFailureNotice`. Recovery actions come from `SessionFailure`, and `SessionRecovery` opens the corresponding permission pane. Keep partial transcripts and summaries visible alongside failures; never choose recovery by searching their text.
