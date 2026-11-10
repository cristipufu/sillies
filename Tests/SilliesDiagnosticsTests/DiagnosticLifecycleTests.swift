import Foundation
import Testing

@testable import SilliesDiagnostics

@Test func diagnosticsExportWindowClosureAndCaptureResourcesThroughTheTypedArchive() async throws {
  let fixture = try DiagnosticFixture()
  defer { fixture.remove() }
  let journal = DiagnosticJournal(directory: fixture.archive, limits: fixture.limits)
  let now = fixture.request().now
  let operation = UUID()
  var closure = DiagnosticEvent(.window, .phaseChanged, operation: operation)
  closure.phase = .closed
  closure.reason = .accessibilityClosure
  var timeout = DiagnosticEvent(.capture, .failed, operation: operation)
  timeout.fault = .finalization
  timeout.resource = .recognition
  try await journal.append(
    [
      .init(event: closure, launch: fixture.launch, sequence: 1, now: now),
      .init(event: timeout, launch: fixture.launch, sequence: 2, now: now),
    ], now: now)
  try await journal.export(fixture.request())
  let events = try fixture.report().events.map(\.event)
  #expect(events == [closure, timeout])
}
