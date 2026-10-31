import Foundation
import SilliesCore
import SilliesModelStore
import SilliesReasoning
import SilliesTextModels

/// Application lifetime owner. Feature modules receive capabilities, never a global locator.
@MainActor final class ReasoningServices {
  let models: TextModelEnvironment
  let reasoning: any LocalReasoning

  init(defaults: UserDefaults = .standard, directory: URL? = nil) {
    let support =
      directory
      ?? FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/Sillies/TextModels", isDirectory: true)
    let preference = TextModelPreference(
      selectedID: defaults.string(forKey: TextModelPreference.key) ?? TextModelEnvironment.appleID,
      save: { defaults.set($0, forKey: TextModelPreference.key) })
    let models = TextModelEnvironment(
      store: ModelStore(root: support), preference: preference,
      providers: [MLXTextModelProvider()])
    self.models = models
    reasoning = LocalReasoningService(resolveBackend: { await models.backend() })
  }

  func makeVault(directory: URL? = nil) -> SessionVaultStore {
    SessionVaultStore(
      directory: directory,
      notesGenerator: { [reasoning] record in
        if record.kind == .stash {
          let (summary, actions) = await SessionSummaryWorker.summarize(
            text: record.primaryText, fallbackContext: record.summary)
          return LocalNotes(summary: summary, actions: actions)
        }
        return await reasoning.notes(
          for: record.primaryText, kind: record.kind, fallback: record.summary,
          localeIdentifier: record.languageIdentifier)
      })
  }
}
