import SilliesCore

/// The catalog and the rendering contracts it must satisfy belong together.
@MainActor
struct CompanionAssets {
  var catalog: CharacterCatalog? = nil
  var renderers = RendererRegistry()
  var animations = AnimationLibrary()
  var transitions = TransitionLibrary()

  func validatedCatalog() throws -> CharacterCatalog {
    let catalog = try catalog ?? CharacterCatalog()
    try catalog.validateAssets(
      renderers: renderers, animations: animations, transitions: transitions)
    return catalog
  }
}
