@MainActor package struct WritingContext {
  package let currentApplication: () -> FrontmostApplication?
  package let vocabularyHints: () -> [String]
  package init(
    currentApplication: @escaping () -> FrontmostApplication?,
    vocabularyHints: @escaping () -> [String]
  ) {
    self.currentApplication = currentApplication
    self.vocabularyHints = vocabularyHints
  }
}
