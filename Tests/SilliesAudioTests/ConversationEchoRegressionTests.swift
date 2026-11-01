import AVFoundation
import Foundation
import SilliesCore
import Testing

@testable import SilliesAudio

@Test(arguments: [0, 0.001, 0.005, 0.02, 0.05, 0.15])
func voiceConversationRejectsEchoAcrossAcousticDelays(delay: Double) async throws {
  try await Task.detached {
    let starts = try ConversationEchoFixture(configuration: .init(echoDelay: delay)).run()
    #expect(starts.isEmpty, "Playback alone opened turns at \(starts), offset \(delay)")
  }.value
}

@Test(arguments: [0.25, 3.0])
func voiceConversationStillAcceptsRealSpeechDuringPlayback(nearStart: Double) async throws {
  try await Task.detached {
    let starts = try ConversationEchoFixture(
      configuration: .init(echoDelay: 0.005, nearStart: nearStart)
    ).run()
    #expect(!starts.contains { $0 < nearStart })
    #expect(starts.contains { $0 >= nearStart && $0 < nearStart + 0.6 })
  }.value
}

@Test(
  arguments: [
    EchoDevicePair(
      render: .init(rate: 48_000, frames: 512), capture: .init(rate: 48_000, frames: 4_800)),
    EchoDevicePair(
      render: .init(rate: 44_100, frames: 512), capture: .init(rate: 48_000, frames: 1_024)),
    EchoDevicePair(
      render: .init(rate: 48_000, frames: 128), capture: .init(rate: 44_100, frames: 4_096)),
    EchoDevicePair(
      render: .init(rate: 16_000, frames: 256), capture: .init(rate: 48_000, frames: 512)),
    EchoDevicePair(
      render: .init(rate: 96_000, frames: 1_024), capture: .init(rate: 48_000, frames: 4_096)),
    EchoDevicePair(
      render: .init(rate: 48_000, frames: 512), capture: .init(rate: 8_000, frames: 256)),
  ], [Optional<Double>.none, .some(3)])
func voiceConversationResamplesDeviceQuantaWithoutSelfInterruption(
  devices: EchoDevicePair, nearStart: Double?
) async throws {
  try await Task.detached {
    let starts = try ConversationEchoFixture(
      configuration: .init(echoDelay: 0.005, nearStart: nearStart, devices: devices)
    ).run()
    if let nearStart {
      #expect(!starts.contains { $0 < nearStart }, "Echo opened turns at \(starts)")
      #expect(starts.contains { $0 >= nearStart && $0 < nearStart + 0.6 })
    } else {
      #expect(starts.isEmpty, "Echo opened turns at \(starts)")
    }
  }.value
}

struct EchoDevicePair: Sendable {
  struct Stream: Sendable {
    let rate: Int
    let frames: Int
  }
  var render = Stream(rate: 16_000, frames: 160)
  var capture = Stream(rate: 16_000, frames: 160)
}

/// Deterministic voiced harmonics exercise real AEC/VAD, acoustic delays and independent callback sizes.
/// No audio device, downloaded model, recording permission, or real-time wait is involved.
private struct ConversationEchoFixture {
  struct Configuration: Sendable {
    let echoDelay: Double
    var nearStart: Double? = nil
    var devices = EchoDevicePair()
  }
  private static let origin: TimeInterval = 100
  private static let durationSeconds = 6
  private static let echoGain: Float = 0.6
  let configuration: Configuration

  func run() throws -> [TimeInterval] {
    let reference = VoicePlaybackReference()
    reference.start()
    let processor = try ConversationAudioProcessor(reference: reference)
    let render = configuration.devices.render
    let capture = configuration.devices.capture
    let renderCount = render.rate * Self.durationSeconds
    let captureCount = capture.rate * Self.durationSeconds
    let playback = (0..<renderCount).map {
      Self.voice(at: Double($0) / Double(render.rate), pitch: 180)
    }
    var renderCursor = 0
    var starts: [TimeInterval] = []
    for cursor in stride(from: 0, to: captureCount, by: capture.frames) {
      let captureEnd = min(cursor + capture.frames, captureCount)
      // Native rendering supplies each output quantum before that audio reaches the microphone.
      while Double(renderCursor) / Double(render.rate) < Double(captureEnd) / Double(capture.rate) {
        let end = min(renderCursor + render.frames, renderCount)
        reference.append(
          .init(
            samples: Array(playback[renderCursor..<end]), sampleRate: Double(render.rate),
            startTime: Self.origin + Double(renderCursor) / Double(render.rate)))
        renderCursor = end
      }
      let microphone = (cursor..<captureEnd).map { microphoneSample($0) }
      try processor.appendMicrophone(
        try buffer(microphone), at: Self.origin + Double(cursor) / Double(capture.rate))
      while let (_, event, end) = try processor.next() {
        if event == .began { starts.append(end - Self.origin) }
      }
    }
    return starts
  }

  private func microphoneSample(_ index: Int) -> Float {
    let rate = Double(configuration.devices.capture.rate)
    let echoed = Double(index) / rate - configuration.echoDelay
    let echo = echoed >= 0 ? Self.voice(at: echoed, pitch: 180) * Self.echoGain : 0
    guard let nearStart = configuration.nearStart else { return echo }
    let time = Double(index) / rate - nearStart
    return echo + (time >= 0 ? Self.voice(at: time, pitch: 287) : 0)
  }

  private static func voice(at time: Double, pitch: Double) -> Float {
    let phase = 2 * Double.pi * (pitch * time + 12 * sin(2 * Double.pi * 3 * time))
    let envelope = min(1, time * 10) * (0.6 + 0.4 * sin(2 * Double.pi * 2 * time))
    return Float(envelope * (0.2 * sin(phase) + 0.1 * sin(3 * phase) + 0.05 * sin(7 * phase)))
  }

  private func buffer(_ samples: [Float]) throws -> AVAudioPCMBuffer {
    let format = try #require(
      AVAudioFormat(
        standardFormatWithSampleRate: Double(configuration.devices.capture.rate), channels: 1))
    let count = try #require(AVAudioFrameCount(exactly: samples.count))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count))
    buffer.frameLength = count
    let destination = try #require(buffer.floatChannelData?[0])
    for (index, value) in samples.enumerated() { destination[index] = value }
    return buffer
  }
}
