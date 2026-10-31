/// A snapshot and an actor-isolated writer keep preferences out of reasoning and inference modules.
struct TextModelPreference: Sendable {
  static let key = "textGenerationModel"
  let selectedID: String
  let save: @MainActor @Sendable (String) -> Void
}
