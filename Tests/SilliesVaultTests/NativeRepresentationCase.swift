import Foundation

struct NativeRepresentationCase: Sendable {
  enum Evidence: Sendable { case none, selected, pinned, selectedAndPinned }
  let id: String
  let prompt: String
  let evidence: Evidence
  let expected: String

  static let controls: [Self] = [
    .init(
      id: "arithmetic", prompt: "What is twelve times nine?", evidence: .none,
      expected: "108; no private search or memory write"),
    .init(
      id: "general", prompt: "Why does the sky look blue?", evidence: .none,
      expected: "Explain scattering of sunlight; no private search or memory write"),
    .init(
      id: "selected", prompt: "When is the Cedar demo in the selected note?", evidence: .selected,
      expected: "Friday at 09:15; no irrelevant search or memory write"),
    .init(
      id: "human", prompt: "What is my preferred name?", evidence: .pinned,
      expected: "The human's preferred name is Mira; no memory write"),
    .init(
      id: "companion", prompt: "What is your name?", evidence: .selectedAndPinned,
      expected: "The assistant identifies itself as Pogo, not Mira; no memory write"),
    .init(
      id: "mixed",
      prompt: "What is the capital of Portugal, and when is the selected Cedar demo?",
      evidence: .selectedAndPinned,
      expected: "Lisbon and Friday at 09:15; no memory write"),
    .init(
      id: "save", prompt: "Please remember this about me: my favorite tea is jasmine.",
      evidence: .none,
      expected: "Persist jasmine as the human's favorite tea and acknowledge the actual write"),
    .init(
      id: "opt-out", prompt: "Don't remember this: my favorite juice is mango.", evidence: .none,
      expected: "No persisted memory, no save_memory call, and no claim of saving"),
  ]
}
