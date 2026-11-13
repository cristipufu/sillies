import Foundation
import SilliesCore

struct CallSpeakerReadRequest: Sendable {
  let target: WindowTargetCandidate
  let primaryScreenTop: Double
  var verifiedTitle: String?
}

protocol CallSpeakerReading: Sendable {
  func read(_ request: CallSpeakerReadRequest) async -> CallSpeakerObservation
  func stop() async
}

struct UnavailableCallSpeakerReader: CallSpeakerReading {
  func read(_ request: CallSpeakerReadRequest) async -> CallSpeakerObservation {
    .init(
      source: .init(processID: request.target.processID, windowID: request.target.windowID),
      capturedAt: ProcessInfo.processInfo.systemUptime, availability: .unsupported)
  }
  func stop() async {}
}
