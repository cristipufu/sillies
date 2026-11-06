import AppKit
import SilliesDiagnostics
import SwiftUI
import Synchronization
import Testing

@testable import SilliesApp
@testable import SilliesAudio

@Test func diagnosticsCaptureBacklogKeepsFailureIdentityAndTimingUnits() throws {
  let events = Mutex<[DiagnosticEvent]>([])
  let sink = DiagnosticSink { event in events.withLock { $0.append(event) } }
  let operation = UUID()
  var timing = AudioCaptureBacklog.Timing()
  timing.record(capturedAt: 10, began: 12, ended: 12.125)
  let backlog = AudioCaptureBacklog(
    pressure: .init(limit: .callbacks, packets: 4_096, bytes: 2_000, sourceDuration: 4),
    timing: timing)
  CaptureDiagnostics.record(backlog, operation: operation, sink: sink)
  let recorded = events.withLock { $0 }
  #expect(recorded.count == 6)
  #expect(recorded.allSatisfy { $0.operation == operation && $0.area == .capture })
  #expect(recorded.first?.action == .failed && recorded.first?.reason == .captureCallbackLimit)
  #expect(recorded.first { $0.metric == .captureQueuedPackets }?.count == 4_096)
  #expect(recorded.first { $0.metric == .captureQueuedAudio }?.milliseconds == 4_000)
  #expect(recorded.first { $0.metric == .captureMaximumQueueWait }?.milliseconds == 2_000)
  #expect(recorded.first { $0.metric == .captureMaximumProcessing }?.milliseconds == 125)
  let encoded = try JSONEncoder().encode(recorded)
  #expect(try JSONDecoder().decode([DiagnosticEvent].self, from: encoded) == recorded)
}

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
