import Foundation
import SilliesInference
import SilliesModelStore
import SilliesVault

@MainActor final class SearchServices {
  let environment: SearchModelEnvironment
  let models: SearchModelsPresentation
  init(
    conversations: ConversationLibrary, defaults: UserDefaults = .standard, directory: URL? = nil
  ) {
    let root =
      directory
      ?? FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/Sillies/SearchModels", isDirectory: true)
    let environment = SearchModelEnvironment(
      store: ModelStore(root: root), conversations: conversations,
      runtime: .init(
        inference: .shared,
        executable: Bundle.main.bundleURL.appendingPathComponent(
          "Contents/Helpers/SilliesSearchInference.app/Contents/MacOS/SilliesSearchInference")),
      selection: .init(
        id: defaults.string(forKey: SearchModelEnvironment.preferenceKey)
          ?? SearchModelEnvironment.appleID,
        save: { defaults.set($0, forKey: SearchModelEnvironment.preferenceKey) }))
    self.environment = environment
    models = SearchModelsPresentation(environment: environment)
  }
}
