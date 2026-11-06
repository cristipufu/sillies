import Foundation
import SilliesCore
import SilliesDiagnostics
import SilliesInference
import SilliesModelStore
import SilliesReasoning
import SilliesTextModels

/// Application lifetime owner. Feature modules receive capabilities, never a global locator.
@MainActor final class ReasoningServices {
  let models: TextModelEnvironment
  let reasoning: any LocalReasoning
  private let turns = ReasoningTurnGate { event in
    switch event {
    case .began: await InferenceActivity.shared.beginInteractiveWork()
    case .ended: await InferenceActivity.shared.endInteractiveWork()
    }
  }

  init(
    defaults: UserDefaults = .standard, directory: URL? = nil,
    diagnostics: DiagnosticSink = .disabled
  ) {
    let support =
      directory
      ?? FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/Sillies/TextModels", isDirectory: true)
    let preference = TextModelPreference(
      selectedID: defaults.string(forKey: TextModelPreference.key) ?? TextModelEnvironment.appleID,
      save: { defaults.set($0, forKey: TextModelPreference.key) })
    let models = TextModelEnvironment(
      store: ModelStore(root: support), preference: preference,
      providers: [MLXTextModelProvider()], diagnostics: diagnostics,
      calibration: TextCalibrationStore(
        directory: support.appendingPathComponent("Calibration"),
        helper: Bundle.main.bundleURL.appendingPathComponent(
          "Contents/Helpers/SilliesTextInference.app/Contents/MacOS/SilliesTextInference")))
    self.models = models
    let service = LocalReasoningService(resolveBackend: { await models.backend() }, turns: turns)
    reasoning = service
  }
  func makeConversation(
    tools: [any ConversationTool],
    history: ConversationHistoryAccess,
    modelSelection: @escaping @Sendable () async -> String? = { nil }
  ) -> any ConversationResponding {
    LocalConversationService(
      resolveBackend: { [models] in await models.backend(overriding: modelSelection()) },
      tools: tools + [ConversationClarificationTool()], turns: turns,
      history: history)
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
