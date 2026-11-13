import Foundation

/// Conservative attribution from supplied recording times. No voice enrollment, timers or clock reads.
public struct CallSpeakerTimeline: Sendable {
  public static let maximumSamples = 512
  public static let retainedDuration: TimeInterval = 120
  public static let maximumHold: TimeInterval = 1.5
  public static let transitionMargin: TimeInterval = 0.75
  private static let minimumCoverage = 0.9
  private struct Sample: Sendable {
    let time: TimeInterval
    let name: CallSpeakerName?
    let isOverlapping: Bool
  }
  public enum Decision: Equatable, Sendable {
    case pending
    case resolved(CallSpeakerName?)
  }
  private var samples: [Sample] = []
  public init() {}
  public var sampleCount: Int { samples.count }
  public var earliestTime: TimeInterval? { samples.first?.time }
  public var latestTime: TimeInterval? { samples.last?.time }

  @discardableResult public mutating func append(
    _ observation: CallSpeakerObservation, at time: TimeInterval
  ) -> Bool {
    guard time.isFinite, time >= 0, samples.last.map({ time >= $0.time }) ?? true else {
      return false
    }
    let sample = Self.sample(observation, time: time)
    if samples.last?.time == time { samples.removeLast() }
    samples.append(sample)
    let cutoff = time - Self.retainedDuration
    while samples.count > 1, samples[1].time < cutoff { samples.removeFirst() }
    if samples.count > Self.maximumSamples {
      samples.removeFirst(samples.count - Self.maximumSamples)
    }
    return true
  }

  public func decision(for range: Range<TimeInterval>) -> Decision {
    guard range.lowerBound.isFinite, range.upperBound.isFinite, range.lowerBound >= 0,
      range.upperBound > range.lowerBound
    else { return .resolved(nil) }
    let start = max(0, range.lowerBound - Self.transitionMargin)
    let end = range.upperBound + Self.transitionMargin
    guard let latestTime, latestTime >= end else { return .pending }
    var covered: TimeInterval = 0
    var names: [String: CallSpeakerName] = [:]
    for index in samples.indices {
      let sample = samples[index]
      let next = index + 1 < samples.count ? samples[index + 1].time : latestTime
      let overlap = min(end, min(next, sample.time + Self.maximumHold)) - max(start, sample.time)
      guard overlap > 0 else { continue }
      if sample.isOverlapping { return .resolved(nil) }
      if let name = sample.name {
        names[name.comparisonKey] = name
        covered += overlap
      }
    }
    guard names.count == 1, covered >= Self.minimumCoverage * (end - start) else {
      return .resolved(nil)
    }
    return .resolved(names.values.first)
  }

  private static func sample(_ observation: CallSpeakerObservation, time: TimeInterval) -> Sample {
    guard observation.availability == .available,
      observation.participants.count <= CallSpeakerObservation.maximumParticipants,
      observation.speaking.count <= CallSpeakerObservation.maximumParticipants
    else {
      return .init(time: time, name: nil, isOverlapping: false)
    }
    let local = observation.localParticipant?.comparisonKey
    let people = Dictionary(
      observation.participants.map { ($0.comparisonKey, $0) },
      uniquingKeysWith: { first, _ in first })
    if observation.roster == .complete, people.count == 2, observation.participants.count == 2,
      let local, people[local] != nil
    {
      return .init(
        time: time, name: people.first(where: { $0.key != local })?.value, isOverlapping: false)
    }
    let others = Dictionary(
      observation.speaking.filter { $0.comparisonKey != local }.map { ($0.comparisonKey, $0) },
      uniquingKeysWith: { first, _ in first })
    return .init(
      time: time, name: others.count == 1 ? others.values.first : nil,
      isOverlapping: others.count > 1)
  }
}
