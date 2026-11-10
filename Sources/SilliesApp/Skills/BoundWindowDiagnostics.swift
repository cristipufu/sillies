import Foundation
import SilliesCore
import SilliesDiagnostics

/// Records changes once per binding, without native identifiers or window content.
@MainActor final class BoundWindowDiagnostics {
  private struct Observation {
    let operation = UUID()
    var visibility: WindowTargetSnapshot.Visibility?
  }
  private let sink: DiagnosticSink
  private var observations: [String: Observation] = [:]

  init(sink: DiagnosticSink) { self.sink = sink }

  func start(for companionID: String) {
    let observation = Observation()
    observations[companionID] = observation
    sink.record(.init(.window, .started, operation: observation.operation))
  }

  func observe(_ snapshot: WindowTargetSnapshot?, target: WindowTargetCandidate, for id: String) {
    guard var observation = observations[id] else { return }
    let visibility: WindowTargetSnapshot.Visibility =
      snapshot?.hasClosed(target) == true ? .closed : snapshot?.visibility ?? .unavailable
    guard observation.visibility != visibility else { return }
    observation.visibility = visibility
    observations[id] = observation
    var event = DiagnosticEvent(.window, .phaseChanged, operation: observation.operation)
    switch visibility {
    case .visible: event.phase = .visible
    case .hidden: event.phase = .hidden
    case .unavailable: event.phase = .unavailable
    case .closed:
      event.phase = .closed
      if let owner = snapshot?.ownerPID, owner != target.processID {
        event.reason = .windowOwnerChanged
      } else {
        event.reason =
          snapshot?.closureEvidence == .accessibility
          ? .accessibilityClosure : .windowServerClosure
      }
    }
    sink.record(event)
  }

  func stop(for id: String, reason: SessionEndReason) {
    guard let observation = observations.removeValue(forKey: id) else { return }
    sink.record(
      .init(.window, .completed, operation: observation.operation)
        .because(reason == .sourceClosed ? .sourceClosed : .sessionClosed))
  }
}
