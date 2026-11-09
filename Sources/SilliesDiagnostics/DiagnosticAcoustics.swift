import Foundation

/// Closed, content-free payload. Unknown JSON fields are discarded by typed decoding and export.
package struct DiagnosticAcoustics: Codable, Sendable, Equatable {
  package enum Boundary: String, Codable, Sendable { case onset, endpoint }
  private static let maximumWindowSamples = 16_000
  private static let signalDecibels: ClosedRange<Double> = -120...0
  private static let echoDecibels: ClosedRange<Double> = -120...120
  private static let referenceAge: ClosedRange<Double> = -2_000...60_000
  private static let echoDelay: ClosedRange<Double> = 0...2_000
  package var boundary: Boundary
  package let utterance: UUID
  package var samples: Int = 0
  package var referenceSamples: Int = 0
  package var clippedSamples: Int = 0
  package var referenceDecibels: Double?
  package var microphoneDecibels: Double?
  package var cleanedDecibels: Double?
  package var droppedReferenceFrames: Int = 0
  package var rejectedReferenceFrames: Int = 0
  package var staleReferenceFrames: Int = 0
  package var referenceDiscontinuities: Int = 0
  package var microphoneDiscontinuities: Int = 0
  package var referenceAgeMilliseconds: Double?
  package var echoDelayMilliseconds: Double?
  package var echoReturnLossDecibels: Double?
  package var echoReductionDecibels: Double?
  package init(boundary: Boundary, utterance: UUID) {
    self.boundary = boundary
    self.utterance = utterance
  }

  func validated() -> Self {
    var value = self
    value.samples = min(Self.maximumWindowSamples, max(0, samples))
    value.referenceSamples = min(value.samples, max(0, referenceSamples))
    value.clippedSamples = min(value.samples, max(0, clippedSamples))
    value.referenceDecibels = bounded(referenceDecibels, within: Self.signalDecibels)
    value.microphoneDecibels = bounded(microphoneDecibels, within: Self.signalDecibels)
    value.cleanedDecibels = bounded(cleanedDecibels, within: Self.signalDecibels)
    value.droppedReferenceFrames = max(0, droppedReferenceFrames)
    value.rejectedReferenceFrames = max(0, rejectedReferenceFrames)
    value.staleReferenceFrames = max(0, staleReferenceFrames)
    value.referenceDiscontinuities = max(0, referenceDiscontinuities)
    value.microphoneDiscontinuities = max(0, microphoneDiscontinuities)
    value.referenceAgeMilliseconds = bounded(referenceAgeMilliseconds, within: Self.referenceAge)
    value.echoDelayMilliseconds = bounded(echoDelayMilliseconds, within: Self.echoDelay)
    value.echoReturnLossDecibels = bounded(echoReturnLossDecibels, within: Self.echoDecibels)
    value.echoReductionDecibels = bounded(echoReductionDecibels, within: Self.echoDecibels)
    return value
  }

  private func bounded(_ value: Double?, within range: ClosedRange<Double>) -> Double? {
    guard let value, value.isFinite else { return nil }
    return min(range.upperBound, max(range.lowerBound, value))
  }
}
