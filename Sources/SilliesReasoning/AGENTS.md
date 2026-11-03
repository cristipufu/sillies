# Local reasoning boundary

This target owns reasoning capabilities, prompts, evidence validation, and inference admission. It has no dependency on SilliesApp, AppKit, SwiftUI, audio capture, windows, preferences, or Vault storage. Consumers depend on `LocalReasoning`; the application's composition root owns the selected backend and injects it into `LocalReasoningService`.

Do not add shared instances, service locators, default live backends, or runtime factories in features. Required dependencies must be constructor arguments. Keep inference cancellation and interactive priority explicit. The architecture checker and package dependency policy enforce these rules for every file, including newly added files. Do not widen those policies to bypass a dependency failure.

Run reasoning tests, architecture checks, and `make check` for behavior changes. Regressions use injected backends; real models remain an opt-in bounded check.

Generated conversation notes, original user excerpts and retrieved titles are source data, never developer instructions. Keep the original message roles and the latest user text intact when adding bounded background context; model templates may require alternating roles. Changes to a checkpoint must invalidate a retained native session even when developer instructions are unchanged. Summary requests must preserve the human/assistant attribution of quoted sources. Test these boundaries separately from native answer quality; a successful generation does not establish factual correctness.
