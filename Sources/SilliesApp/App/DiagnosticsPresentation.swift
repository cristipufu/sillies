import Foundation
import Observation
import SilliesDiagnostics

@MainActor @Observable final class DiagnosticsPresentation {
  private(set) var enabled: Bool
  private(set) var isBusy = false
  private(set) var failure: String?
  private(set) var status: String?
  private let recorder: DiagnosticRecorder
  private let savePreference: @MainActor (Bool) -> Void

  init(
    recorder: DiagnosticRecorder, enabled: Bool,
    savePreference: @escaping @MainActor (Bool) -> Void
  ) {
    self.recorder = recorder
    self.enabled = enabled
    self.savePreference = savePreference
  }

  func refresh() {
    if enabled, recorder.failure != nil { storageFailed() }
  }

  func setEnabled(_ value: Bool) async {
    guard !isBusy else { return }
    isBusy = true
    defer { isBusy = false }
    enabled = value
    savePreference(value)
    await recorder.setEnabled(value)
    failure = nil
    status = nil
    if value {
      do { try await recorder.start() } catch { storageFailed() }
    }
  }

  func clear() async {
    guard !isBusy else { return }
    isBusy = true
    defer { isBusy = false }
    do {
      try await recorder.clear()
      failure = nil
      status = String(localized: "Local diagnostics cleared.")
    } catch { storageFailed() }
  }

  func export(to destination: URL) async {
    guard !isBusy else { return }
    isBusy = true
    failure = nil
    status = nil
    defer { isBusy = false }
    do {
      try await recorder.export(to: destination, environment: .init())
      status = String(
        localized: "Diagnostics exported. You can share this file when reporting a problem.")
    } catch {
      failure = String(
        localized: "Couldn’t export diagnostics. Check available disk space and folder access.")
    }
  }

  private func storageFailed() {
    failure = String(
      localized:
        "Diagnostics couldn’t be saved. Check disk space, then turn diagnostics off and on to retry."
    )
  }
}
