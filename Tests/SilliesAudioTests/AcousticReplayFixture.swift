import AVFoundation
import Foundation
import SilliesCore
import SilliesSpeech
import Testing

@testable import SilliesAudio

/// Sample-time replay, with independently delivered render quanta. Never opens an audio device.
struct AcousticReplayFixture {
  enum Scenario: String, CaseIterable, Sendable {
    case steady, phraseRestarts, reverberation, gainChange, clipping
    case callbackJitter, missingReference, lateReference, clockDrift, quietInterruption,
      shortInterruption
  }
  struct Signals: Sendable {
    let far: [Float]
    let near: [Float]
    static func synthetic() -> Self {
      let rate = Double(MeetingAudioTimeline.sampleRate)
      return .init(
        far: (0..<MeetingAudioTimeline.sampleRate).map { voiced(Double($0) / rate, pitch: 180) },
        near: (0..<MeetingAudioTimeline.sampleRate).map { voiced(Double($0) / rate, pitch: 287) })
    }
    static func prerecorded(far: String, near: String) throws -> Self {
      let nearSamples = try read(near)
      let speechStart = nearSamples.firstIndex { abs($0) >= 0.01 } ?? nearSamples.endIndex
      return try .init(far: read(far), near: Array(nearSamples[speechStart...]))
    }
    private static func read(_ path: String) throws -> [Float] {
      let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
      let count = try #require(AVAudioFrameCount(exactly: file.length))
      let buffer = try #require(
        AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: count))
      try file.read(into: buffer)
      let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
      let converted = try SpeechBufferConverter(format: format).convert(buffer)
      let samples = try #require(converted.floatChannelData?[0])
      return Array(UnsafeBufferPointer(start: samples, count: Int(converted.frameLength)))
    }
    private static func voiced(_ time: Double, pitch: Double) -> Float {
      let phase = 2 * Double.pi * (pitch * time + 12 * sin(2 * Double.pi * 3 * time))
      let envelope = min(1, time * 10) * (0.6 + 0.4 * sin(2 * Double.pi * 2 * time))
      return Float(envelope * (0.2 * sin(phase) + 0.1 * sin(3 * phase) + 0.05 * sin(7 * phase)))
    }
  }
  struct Report {
    let starts: [TimeInterval]
    let boundaries: [VoiceAcousticEvidence]
    let checkpoint: VoiceAcousticEvidence
    let final: VoiceAcousticEvidence
  }
  private static let origin: TimeInterval = 100
  private static let duration: TimeInterval = 8
  private static let checkpointTime: TimeInterval = 3.5
  private static let nearStart: TimeInterval = 5
  private static let sampleRate = MeetingAudioTimeline.sampleRate
  private static let renderFrames = 128
  private static let captureFrames = 160
  private static let echoDelay: TimeInterval = 0.02
  let scenario: Scenario
  let signals: Signals

  func run() throws -> Report {
    let reference = VoicePlaybackReference()
    reference.start()
    let processor = try ConversationAudioProcessor(reference: reference)
    let count = Int(Self.duration * Double(Self.sampleRate))
    let far = (0..<count).map { farSample(at: Double($0) / Double(Self.sampleRate) * clockScale) }
    var renderCursor = 0
    var starts: [TimeInterval] = []
    var boundaries: [VoiceAcousticEvidence] = []
    var checkpoint: VoiceAcousticEvidence?
    for cursor in stride(from: 0, to: count, by: Self.captureFrames) {
      let end = min(count, cursor + Self.captureFrames)
      let captureEnd = Double(end) / Double(Self.sampleRate)
      while renderCursor < count {
        let renderTime = Double(renderCursor) / Double(Self.sampleRate) * clockScale
        guard renderTime + deliveryDelay(at: renderTime) < captureEnd else { break }
        let renderEnd = min(count, renderCursor + Self.renderFrames)
        if scenario != .missingReference || !(2...3.4).contains(renderTime) {
          reference.append(
            .init(
              samples: Array(far[renderCursor..<renderEnd]), sampleRate: Double(Self.sampleRate),
              startTime: Self.origin + renderTime))
        }
        renderCursor = renderEnd
      }
      let samples = (cursor..<end).map {
        microphoneSample(at: Double($0) / Double(Self.sampleRate))
      }
      try processor.appendMicrophone(
        try buffer(samples), at: Self.origin + Double(cursor) / Double(Self.sampleRate))
      while let (_, event, end) = try processor.next() {
        if event == .began {
          starts.append(end - Self.origin)
          boundaries.append(processor.assessment(at: .onset))
        } else if event == .ended {
          boundaries.append(processor.assessment(at: .endpoint))
          processor.beginNextTurn()
        }
        if checkpoint == nil, end >= Self.origin + Self.checkpointTime {
          checkpoint = processor.assessment(at: .onset)
        }
      }
    }
    return Report(
      starts: starts, boundaries: boundaries,
      checkpoint: checkpoint ?? processor.assessment(at: .onset),
      final: processor.assessment(at: .endpoint))
  }

  private var clockScale: Double { scenario == .clockDrift ? 1.000_15 : 1 }
  private func deliveryDelay(at time: TimeInterval) -> TimeInterval {
    if scenario == .lateReference { return 0.18 }
    return scenario == .callbackJitter && Int(time * 10) % 5 == 0 ? 0.06 : 0
  }
  private func farSample(at time: TimeInterval) -> Float {
    guard time >= 0, !signals.far.isEmpty else { return 0 }
    if scenario == .phraseRestarts, time.truncatingRemainder(dividingBy: 2) >= 1.1 { return 0 }
    let position = time / clockScale * Double(Self.sampleRate)
    let index = Int(position.rounded(.down))
    let fraction = Float(position - Double(index))
    let first = signals.far[index % signals.far.count]
    let second = signals.far[(index + 1) % signals.far.count]
    return first + fraction * (second - first)
  }
  private func microphoneSample(at time: TimeInterval) -> Float {
    let gain: Float = scenario == .gainChange && time >= 3 ? 0.9 : 0.6
    var echo = gain * farSample(at: time - Self.echoDelay)
    if scenario == .reverberation {
      echo +=
        0.25 * farSample(at: time - 0.06) + 0.1 * farSample(at: time - 0.11)
        + 0.05 * farSample(at: time - 0.2)
    }
    if scenario == .clipping { echo = max(-1, min(1, echo * 12)) }
    let nearTime = time - Self.nearStart
    if scenario == .quietInterruption || scenario == .shortInterruption,
      nearTime >= 0, !signals.near.isEmpty,
      nearTime < (scenario == .shortInterruption ? 0.4 : 2)
    {
      let index = Int(nearTime * Double(Self.sampleRate)) % signals.near.count
      return echo + signals.near[index] * (scenario == .quietInterruption ? 0.25 : 1)
    }
    return echo
  }
  private func buffer(_ samples: [Float]) throws -> AVAudioPCMBuffer {
    let format = try #require(
      AVAudioFormat(standardFormatWithSampleRate: Double(Self.sampleRate), channels: 1))
    let count = try #require(AVAudioFrameCount(exactly: samples.count))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count))
    buffer.frameLength = count
    try #require(buffer.floatChannelData?[0]).update(from: samples, count: samples.count)
    return buffer
  }
}
