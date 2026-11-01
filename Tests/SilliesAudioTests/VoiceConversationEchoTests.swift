import AVFoundation
import Foundation
import SilliesCore
import SilliesSpeech
import Testing

@testable import SilliesAudio

/// Optional prerecorded speech check: no capture permission, audio device, model or wall-clock playback.
@Test(.enabled(if: ProcessInfo.processInfo.environment["SILLIES_VOICE_ECHO_FIXTURE"] != nil))
func voiceConversationEchoReferenceSuppressesPlaybackAndDetectsInterruption() async throws {
  let path = try #require(ProcessInfo.processInfo.environment["SILLIES_VOICE_ECHO_FIXTURE"])
  try await Task.detached {
    let far = try fixtureSamples(path)
    let near = try fixtureSamples(path + ".near.aiff")
    let rate = MeetingAudioTimeline.sampleRate
    let reference = VoicePlaybackReference()
    reference.start()
    let processor = try ConversationAudioProcessor(reference: reference)
    let delay = rate / 20
    let count = rate * 14
    let playback = (0..<count).map { far[$0 % far.count] }
    var speechStarts: [TimeInterval] = []
    var microphoneEnergy = 0.0
    var residualEnergy = 0.0
    for start in stride(from: 0, to: count, by: MeetingAudioTimeline.frameSamples) {
      let range = start..<(start + MeetingAudioTimeline.frameSamples)
      let time = 100 + Double(start) / Double(rate)
      let microphone = range.map { index -> Float in
        let echo = index >= delay ? playback[index - delay] * 0.6 : 0
        let secondEcho = index >= delay * 2 ? playback[index - delay * 2] * 0.2 : 0
        let user =
          index >= rate * 9 && index < rate * 12 ? near[(index - rate * 9) % near.count] : 0
        return echo + secondEcho + user
      }
      reference.append(
        .init(samples: Array(playback[range]), sampleRate: Double(rate), startTime: time))
      try processor.appendMicrophone(try pcm(microphone), at: time)
      if start >= rate * 5 && start < rate * 8 {
        microphoneEnergy += microphone.reduce(0) { $0 + Double($1 * $1) }
      }
      while let (cleaned, event, end) = try processor.next() {
        if event == .began { speechStarts.append(end - 100) }
        if end >= 105 && end < 108, let samples = cleaned.floatChannelData?[0] {
          residualEnergy += (0..<Int(cleaned.frameLength)).reduce(0) {
            $0 + Double(samples[$1] * samples[$1])
          }
        }
      }
    }
    let reduction = 10 * log10(microphoneEnergy / max(residualEnergy, 1e-12))
    print("CHAT AEC: echo reduction \(reduction) dB; speech starts \(speechStarts)")
    #expect(reduction > 20)
    #expect(!speechStarts.contains { $0 < 9 })
    #expect(speechStarts.contains { $0 >= 9 && $0 < 10.5 })
  }.value
}

@Test func voiceConversationFlushesHeldAudioAtStop() async throws {
  try await Task.detached {
    let processor = try ConversationAudioProcessor(reference: VoicePlaybackReference())
    // A sub-holdback tail is deliberately invisible to live processing and must survive stop.
    try processor.appendMicrophone(try pcm([Float](repeating: 0.02, count: 1_280)), at: 100)
    #expect(try processor.next() == nil)
    var count = 0
    while let buffer = try processor.nextFinalMicrophone() { count += Int(buffer.frameLength) }
    #expect(count == 1_280)
  }.value
}

@Test func voiceConversationWaitsForMicrophoneWhenOutputHasHighLatency() async throws {
  try await Task.detached {
    let reference = VoicePlaybackReference()
    reference.start()
    let processor = try ConversationAudioProcessor(reference: reference)
    reference.append(
      .init(samples: [Float](repeating: 0.1, count: 1_600), sampleRate: 16_000, startTime: 100.3))
    try processor.appendMicrophone(try pcm([Float](repeating: 0.02, count: 1_280)), at: 100)
    #expect(try processor.next() == nil)
    try processor.appendMicrophone(try pcm([Float](repeating: 0.02, count: 1_280)), at: 100.08)
    var samples = 0
    while let (buffer, _, end) = try processor.next() {
      samples += Int(buffer.frameLength)
      #expect(end <= 100.04)
    }
    #expect(samples > 0)
    while let buffer = try processor.nextFinalMicrophone() { samples += Int(buffer.frameLength) }
    #expect(samples == 2_560)
  }.value
}

private func fixtureSamples(_ path: String) throws -> [Float] {
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

private func pcm(_ samples: [Float]) throws -> AVAudioPCMBuffer {
  let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
  let count = try #require(AVAudioFrameCount(exactly: samples.count))
  let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count))
  buffer.frameLength = count
  let data = try #require(buffer.floatChannelData?[0])
  for (index, value) in samples.enumerated() { data[index] = value }
  return buffer
}
