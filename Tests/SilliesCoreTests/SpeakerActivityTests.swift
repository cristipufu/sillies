import Foundation
import SilliesCore
import Testing

@Test func speakerActivityDistinguishesTurnsFromOverlappingSpeech() throws {
  var timeline = SpeakerActivityTimeline()
  try timeline.append(
    .init(
      start: 0, frameDuration: 0.1, speakerCount: 2,
      probabilities: Array(repeating: [Float(0.95), 0.02], count: 10).flatMap { $0 }))
  try timeline.append(
    .init(
      start: 1, frameDuration: 0.1, speakerCount: 2,
      probabilities: Array(repeating: [Float(0.02), 0.95], count: 10).flatMap { $0 }))
  #expect(timeline.speaker(in: 0..<1) == .identified(1))
  #expect(timeline.speaker(in: 1..<2) == .identified(2))
  #expect(timeline.speaker(in: 0..<2) == .unknown)
  #expect(timeline.speaker(in: 2..<3) == .unknown)
  try timeline.append(
    .init(
      start: 2, frameDuration: 0.1, speakerCount: 2,
      probabilities: Array(repeating: [Float(0.9), 0.9], count: 10).flatMap { $0 }))
  #expect(timeline.speaker(in: 2..<3) == .overlapping([1, 2]))
}

@Test func speakerActivityRetainsBoundedHistoryAcrossEightVirtualHours() throws {
  var timeline = SpeakerActivityTimeline()
  let probabilities: [Float] = Array(repeating: [Float(0.95), Float(0.01)], count: 100).flatMap {
    $0
  }
  for start in stride(from: 0.0, to: 8 * 60 * 60, by: 10) {
    try timeline.append(
      .init(start: start, frameDuration: 0.1, speakerCount: 2, probabilities: probabilities))
    #expect(timeline.retainedFrameCount <= 6_000)
  }
  #expect(timeline.processedThrough == 8 * 60 * 60)
  #expect(timeline.speaker(in: 0..<1) == .unknown)
  #expect(timeline.speaker(in: 28_799..<28_800) == .identified(1))
}

@Test func malformedSpeakerActivityDoesNotCorruptExistingIdentity() throws {
  var timeline = SpeakerActivityTimeline()
  try timeline.append(.init(start: 0, frameDuration: 0.1, speakerCount: 1, probabilities: [0.9]))
  #expect(throws: SpeakerActivityTimeline.Failure.self) {
    try timeline.append(.init(start: 0.1, frameDuration: .nan, speakerCount: 2, probabilities: [1]))
  }
  #expect(timeline.speaker(in: 0..<0.1) == .identified(1))
}
