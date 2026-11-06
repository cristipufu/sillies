import AppKit
import SilliesDiagnostics
import SwiftUI
import Testing

@testable import SilliesApp

@Test @MainActor func diagnosticsSettingsExportClearAndDisableWithoutPresentingWindows()
  async throws
{
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let recorder = DiagnosticRecorder(
    directory: directory.appendingPathComponent("logs"), enabled: true)
  try await recorder.start()
  var savedPreference = true
  let model = DiagnosticsPresentation(
    recorder: recorder, enabled: true, savePreference: { savedPreference = $0 })
  recorder.sink.record(.init(.chat, .cancelled).because(.userStop))
  let export = directory.appendingPathComponent("diagnostics.json")
  await model.export(to: export)
  #expect(model.failure == nil && model.status != nil && !model.isBusy)
  let data = try Data(contentsOf: export)
  #expect(String(decoding: data, as: UTF8.self).contains("userStop"))
  for scheme in [ColorScheme.light, .dark] {
    try renderSkillInterface(
      DiagnosticsSettingsView(model: model, export: {}).padding(16).environment(
        \.colorScheme, scheme),
      size: CGSize(width: 540, height: 300), name: "sillies-diagnostics-\(scheme)")
  }
  await model.setEnabled(false)
  await model.clear()
  #expect(!savedPreference && !model.enabled && model.failure == nil)
  recorder.sink.record(.init(.chat, .started))
  await model.export(to: export)
  let report = try #require(
    JSONSerialization.jsonObject(with: Data(contentsOf: export)) as? [String: Any])
  #expect((report["events"] as? [Any])?.isEmpty == true)
  await model.export(to: directory.appendingPathComponent("missing/report.json"))
  #expect(model.failure != nil && !model.isBusy)
  await recorder.shutdown()
}

@Test @MainActor func diagnosticsShutdownFlushesDuringTheNativeModalTerminationLoop() throws {
  let domain = "sillies-diagnostics-\(UUID())"
  let defaults = try #require(UserDefaults(suiteName: domain))
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(domain)
  defer {
    defaults.removePersistentDomain(forName: domain)
    removeTestFile(at: directory)
  }
  let service = DiagnosticServices(defaults: defaults, directory: directory)
  service.start()
  service.sink.record(.init(.chat, .cancelled).because(.sessionClosed))
  var completed = false
  service.shutdown { completed = true }
  let deadline = Date().addingTimeInterval(3)
  while !completed && Date() < deadline {
    CFRunLoopRunInMode(CFRunLoopMode(RunLoop.Mode.modalPanel.rawValue as CFString), 0.01, true)
  }
  #expect(completed)
  let file = directory.appendingPathComponent("events-0.jsonl")
  let events = try String(contentsOf: file, encoding: .utf8)
  #expect(events.contains("sessionClosed") && events.contains("completed"))
}
