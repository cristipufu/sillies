import Foundation

/// Numeric evidence about a bounded acoustic window. Contains no sound, words or device identity.
package struct VoiceAcousticEvidence: Sendable, Equatable {
  package enum Boundary: String, Sendable { case onset, endpoint }

  package struct Window: Sendable, Equatable {
    private static let silenceDecibels = -120.0
    package var samples = 0
    package var referenceSamples = 0
    package var referenceDecibels = Window.silenceDecibels
    package var microphoneDecibels = Window.silenceDecibels
    package var cleanedDecibels = Window.silenceDecibels
    package var clippedSamples = 0
    package init() {}
  }

  package struct Delivery: Sendable, Equatable {
    package var droppedReferenceFrames = 0
    package var rejectedReferenceFrames = 0
    package var staleReferenceFrames = 0
    package var referenceDiscontinuities = 0
    package var microphoneDiscontinuities = 0
    package var referenceAgeMilliseconds: Double?
    package init() {}
  }

  package struct Echo: Sendable, Equatable {
    package var delayMilliseconds: Double?
    package var returnLossDecibels: Double?
    package var reductionDecibels: Double?
    package init() {}
  }

  package let boundary: Boundary
  package let window: Window
  package let delivery: Delivery
  package let echo: Echo

  package init(boundary: Boundary, window: Window, delivery: Delivery, echo: Echo) {
    self.boundary = boundary
    self.window = window
    self.delivery = delivery
    self.echo = echo
  }
}
