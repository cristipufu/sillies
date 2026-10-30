import Foundation

public struct SpeakerActivityBatch: Sendable {
  public let start: TimeInterval
  public let frameDuration: TimeInterval
  public let speakerCount: Int
  public let probabilities: [Float]
  public var frameCount: Int { probabilities.count / max(1, speakerCount) }
  public var end: TimeInterval { start + Double(frameCount) * frameDuration }

  public init(
    start: TimeInterval, frameDuration: TimeInterval, speakerCount: Int, probabilities: [Float]
  ) {
    self.start = start
    self.frameDuration = frameDuration
    self.speakerCount = speakerCount
    self.probabilities = probabilities
  }

  public func shifted(by offset: TimeInterval) -> Self {
    Self(
      start: start + offset, frameDuration: frameDuration, speakerCount: speakerCount,
      probabilities: probabilities)
  }
}
