import Foundation
import SilliesDiagnostics
import SilliesInference

/// App lifetime owns the archive. Feature modules receive only its content-free event sink.
@MainActor final class DiagnosticServices {
  private static let preferenceKey = "localDiagnosticsEnabled"
  let recorder: DiagnosticRecorder
  let presentation: DiagnosticsPresentation
  var sink: DiagnosticSink { recorder.sink }
  private var startup: Task<Void, Never>?

  init(defaults: UserDefaults = .standard, directory: URL? = nil) {
    let enabled = defaults.object(forKey: Self.preferenceKey) as? Bool ?? true
    recorder = DiagnosticRecorder(
      directory: directory
        ?? FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Sillies/Diagnostics", isDirectory: true),
      enabled: enabled)
    presentation = DiagnosticsPresentation(
      recorder: recorder, enabled: enabled,
      savePreference: { defaults.set($0, forKey: Self.preferenceKey) })
  }

  func start() {
    guard startup == nil else { return }
    startup = Task.detached(priority: .utility) { [recorder, presentation] in
      do {
        try await recorder.start()
        guard !Task.isCancelled else { return }
        await InferenceActivity.shared.setDiagnostics(recorder.sink)
        recorder.sink.record(.init(.app, .started))
      } catch { MainRunLoopDelivery.perform { presentation.refresh() } }
    }
  }

  func shutdown(completion: @escaping @MainActor @Sendable () -> Void) {
    let starting = startup
    startup?.cancel()
    startup = nil
    Task.detached(priority: .utility) { [recorder] in
      await starting?.value
      await InferenceActivity.shared.setDiagnostics(.disabled)
      recorder.sink.record(.init(.app, .completed))
      await recorder.shutdown()
      MainRunLoopDelivery.perform(completion)
    }
  }
}
