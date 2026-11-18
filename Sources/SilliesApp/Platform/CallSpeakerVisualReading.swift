import CoreGraphics
import Foundation
import SilliesCore

struct CallSpeakerVisualRequest: Sendable {
  let source: CallSpeakerObservation.Source
  let layout: CallSpeakerVisualLayout
  let interpreter: any CallSpeakerVisualInterpreting
}

struct CallSpeakerVisualObservation: Sendable {
  let capturedAt: TimeInterval
  let speaking: [CallSpeakerName]
}

protocol CallSpeakerVisualReading: Sendable {
  func read(_ request: CallSpeakerVisualRequest) async -> CallSpeakerVisualObservation?
  func stop() async
}

protocol CallSpeakerImageCapturing: Sendable {
  func capture(_ request: CallSpeakerVisualRequest) async -> CGImage?
  func stop() async
}

protocol CallSpeakerVisualInterpreting: Sendable {
  func speakers(in image: CGImage, layout: CallSpeakerVisualLayout) -> [CallSpeakerName]?
}
