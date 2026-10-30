import Foundation

/// Only recent activity is retained. Final transcript labels do not depend on this cache.
public struct SpeakerActivityTimeline: Sendable {
  public enum Failure: Error { case invalidPredictions }
  private struct Frame: Sendable {
    let range: Range<TimeInterval>
    let probabilities: [Float]
  }
  private static let maximumFrames = 6_000
  private static let maximumBatchFrames = 3_200
  private static let maximumSpeakers = 16
  private static let activityThreshold: Float = 0.5
  private static let minimumCoverage = 0.6
  private static let minimumConfidence = 0.4
  private static let overlapFraction = 0.25
  private static let dominanceMargin = 0.12
  private var frames: [Frame] = []
  public private(set) var processedThrough: TimeInterval = 0
  public var retainedFrameCount: Int { frames.count }
  public init() {}

  public mutating func append(_ batch: SpeakerActivityBatch) throws {
    guard batch.start.isFinite, batch.start >= 0, batch.frameDuration.isFinite,
      batch.frameDuration >= 0.001, batch.frameDuration <= 1,
      (1...Self.maximumSpeakers).contains(batch.speakerCount),
      batch.probabilities.count.isMultiple(of: batch.speakerCount),
      batch.frameCount <= Self.maximumBatchFrames,
      batch.probabilities.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
      batch.start + 0.001 >= processedThrough
    else { throw Failure.invalidPredictions }
    for frame in 0..<batch.frameCount {
      let start = batch.start + Double(frame) * batch.frameDuration
      let index = frame * batch.speakerCount
      frames.append(
        Frame(
          range: start..<(start + batch.frameDuration),
          probabilities: Array(batch.probabilities[index..<(index + batch.speakerCount)])))
    }
    if frames.count > Self.maximumFrames { frames.removeFirst(frames.count - Self.maximumFrames) }
    processedThrough = max(processedThrough, batch.end)
  }

  public func speaker(in range: Range<TimeInterval>) -> TranscriptSpeaker {
    let duration = range.upperBound - range.lowerBound
    guard duration.isFinite, duration > 0 else { return .unknown }
    var totals = [Double](repeating: 0, count: Self.maximumSpeakers)
    var concurrent = [Double](repeating: 0, count: Self.maximumSpeakers)
    var coverage = 0.0
    for frame in frames.reversed() {
      if frame.range.upperBound <= range.lowerBound { break }
      let shared =
        min(frame.range.upperBound, range.upperBound)
        - max(frame.range.lowerBound, range.lowerBound)
      guard shared > 0 else { continue }
      coverage += shared
      let active = frame.probabilities.indices.filter {
        frame.probabilities[$0] >= Self.activityThreshold
      }
      for index in frame.probabilities.indices {
        totals[index] += Double(frame.probabilities[index]) * shared
      }
      if active.count > 1 { for index in active { concurrent[index] += shared } }
    }
    guard coverage >= duration * Self.minimumCoverage else { return .unknown }
    let overlapping = concurrent.indices.filter {
      concurrent[$0] >= coverage * Self.overlapFraction
    }
    if overlapping.count > 1 { return .overlapping(overlapping.map { $0 + 1 }) }
    let ranked = totals.indices.sorted { totals[$0] > totals[$1] }
    guard let first = ranked.first, totals[first] / coverage >= Self.minimumConfidence,
      (totals[first] - totals[ranked[1]]) / coverage >= Self.dominanceMargin
    else { return .unknown }
    return .identified(first + 1)
  }
}
