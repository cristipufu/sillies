import Foundation
import SilliesAudio
import SilliesCore
import SilliesDiagnostics
import Synchronization
import Testing

@testable import SilliesApp

@Test @MainActor func meetingDiagnosticsRecordTransitionsAndClosureWithoutWindowContent() throws {
  let events = Mutex<[DiagnosticEvent]>([])
  let diagnostics = BoundWindowDiagnostics(
    sink: .init { event in events.withLock { $0.append(event) } })
  let target = WindowTargetCandidate(
    windowID: 42, processID: 123, appName: "private app", windowTitle: "private meeting",
    frame: .zero)
  diagnostics.start(for: "private companion")
  let visible = WindowTargetSnapshot(frame: .zero, title: "private meeting", ownerPID: 123)
  diagnostics.observe(visible, target: target, for: "private companion")
  diagnostics.observe(visible, target: target, for: "private companion")
  diagnostics.observe(nil, target: target, for: "private companion")
  diagnostics.observe(
    .init(frame: .zero, title: nil, visibility: .closed, closureEvidence: .accessibility),
    target: target, for: "private companion")
  diagnostics.stop(for: "private companion", reason: .sourceClosed)
  diagnostics.stop(for: "private companion", reason: .sourceClosed)
  let recorded = events.withLock { $0 }
  #expect(recorded.count == 5)
  #expect(recorded.map(\.phase) == [nil, .visible, .unavailable, .closed, nil])
  #expect(recorded[3].reason == .accessibilityClosure)
  #expect(recorded.last?.reason == .sourceClosed)
  #expect(Set(recorded.compactMap(\.operation)).count == 1)
  #expect(!String(decoding: try JSONEncoder().encode(recorded), as: UTF8.self).contains("private"))
}

@Test func meetingDiagnosticsIdentifyTimedOutResourcesWithoutRawFailureDescriptions() throws {
  let events = Mutex<[DiagnosticEvent]>([])
  let sink = DiagnosticSink { event in events.withLock { $0.append(event) } }
  let operation = UUID()
  for event: AudioCaptureLifecycleEvent in [
    .capturing, .finishing(.sourceClosed), .resourceStopped(.application),
    .resourceTimedOut(.speech),
    .failed(.init(category: .captureInterrupted, message: "private native error /Users/private")),
    .finished,
  ] {
    CaptureDiagnostics.record(event, operation: operation, sink: sink)
  }
  let recorded = events.withLock { $0 }
  #expect(recorded.count == 6)
  #expect(recorded[1].reason == .sourceClosed)
  #expect(recorded[2].resource == .applicationAudio)
  #expect(recorded[3].resource == .recognition && recorded[3].fault == .finalization)
  #expect(recorded[4].fault == .captureInterrupted)
  #expect(recorded.allSatisfy { $0.operation == operation })
  #expect(!String(decoding: try JSONEncoder().encode(recorded), as: UTF8.self).contains("private"))
}
