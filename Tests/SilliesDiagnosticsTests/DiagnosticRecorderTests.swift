import Foundation
import Testing

@testable import SilliesDiagnostics

@Test func diagnosticsBoundConcurrentProducersAndDiscloseDroppedEvents() async throws {
  let fixture = try DiagnosticFixture()
  defer { fixture.remove() }
  var limits = fixture.limits
  limits.pendingEvents = 8
  let recorder = DiagnosticRecorder(directory: fixture.archive, enabled: true, limits: limits)
  try await recorder.start()
  let sink = recorder.sink
  await withTaskGroup(of: Void.self) { group in
    for _ in 0..<8 {
      group.addTask {
        for _ in 0..<1_000 { sink.record(.init(.chat, .started, operation: UUID())) }
      }
    }
  }
  #expect(recorder.pendingCount <= limits.pendingEvents)
  #expect(recorder.droppedCount > 0)
  try await recorder.export(to: fixture.export, environment: .init())
  #expect(recorder.failure == nil)
  #expect(try Data(contentsOf: fixture.export).count <= limits.exportBytes)
  let report =
    try JSONSerialization.jsonObject(with: Data(contentsOf: fixture.export)) as? [String: Any]
  let metadata = try #require(report?["metadata"] as? [String: Any])
  #expect(try #require(metadata["droppedEvents"] as? Int) > 0)
  await recorder.shutdown()
}

@Test func diagnosticsClearDisableAndShutdownRejectLateProducersAcrossRestart() async throws {
  let fixture = try DiagnosticFixture()
  defer { fixture.remove() }
  let recorder = DiagnosticRecorder(
    directory: fixture.archive, enabled: true, limits: fixture.limits)
  try await recorder.start()
  let sink = recorder.sink
  sink.record(.init(.app, .started))
  await recorder.setEnabled(false)
  try await recorder.clear()
  for _ in 0..<100 { sink.record(.init(.chat, .started)) }
  try await recorder.export(to: fixture.export, environment: .init())
  #expect(try fixture.report().events.isEmpty)
  await recorder.setEnabled(true)
  sink.record(.init(.chat, .cancelled).because(.userStop))
  await recorder.shutdown()
  sink.record(.init(.chat, .started))
  let reopened = DiagnosticRecorder(
    directory: fixture.archive, enabled: false, limits: fixture.limits)
  try await reopened.start()
  try await reopened.export(to: fixture.export, environment: .init())
  #expect(try fixture.report().events.map(\.event.reason) == [.userStop])
  await reopened.shutdown()
}

@Test func diagnosticsReportStorageFailureWithoutRecursiveLoggingOrLosingControl() async throws {
  let fixture = try DiagnosticFixture()
  defer { fixture.remove() }
  try Data("not a directory".utf8).write(to: fixture.archive)
  let recorder = DiagnosticRecorder(directory: fixture.archive, enabled: true)
  await #expect(throws: (any Error).self) { try await recorder.start() }
  #expect(recorder.failure != nil)
  for _ in 0..<1_000 { recorder.sink.record(.init(.synthesis, .failed)) }
  #expect(recorder.pendingCount == 0)
  try FileManager.default.removeItem(at: fixture.archive)
  await recorder.setEnabled(false)
  await recorder.setEnabled(true)
  try await recorder.start()
  recorder.sink.record(.init(.app, .started))
  try await recorder.export(to: fixture.export, environment: .init())
  #expect(recorder.failure == nil)
  #expect(try fixture.report().events.contains { $0.event.action == .started })
  await recorder.shutdown()
}
