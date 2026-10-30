import AVFoundation
import Foundation
import SilliesAudioTestSupport
import SilliesCore
import SilliesSpeech
import SilliesSpeechApple
import Testing

@testable import SilliesApp
@testable import SilliesAudio

private final class EchoTranscriptOutput: @unchecked Sendable {
  private let lock = NSLock()
  private var transcript = SpeechTranscript()
  private var failures: [String] = []
  func receive(_ phrase: SpeechPhrase) {
    lock.withLock {
      transcript.receive(phrase, source: .microphone, elapsed: phrase.startTime ?? 0)
    }
  }
  func failed(_ message: String) { lock.withLock { failures.append(message) } }
  var snapshot: (String, [String]) { lock.withLock { (transcript.text, failures) } }
}

/// Synthetic speech with delayed speaker echo; never captures the room or changes audio devices.
@Test(.enabled(if: ProcessInfo.processInfo.environment["SILLIES_ECHO_SPEECH_CHECK"] == "1"))
@MainActor func localSpeechWithEchoCancellationPreservesNearSpeakerDuringInteraction() async throws
{
  let farPath = try #require(ProcessInfo.processInfo.environment["SILLIES_SPEECH_FIXTURE"])
  let nearPath = try #require(ProcessInfo.processInfo.environment["SILLIES_NEAR_SPEECH_FIXTURE"])
  let outputs = [EchoTranscriptOutput(), EchoTranscriptOutput()]
  var channels: [any LocalSpeechChannel] = []
  for output in outputs {
    channels.append(
      try await AppleSpeechProvider.makeChannel(
        language: fixtureEnglish, output: { output.receive($0) }, failure: { output.failed($0) }))
  }
  let activeChannels = channels
  let task = Task.detached(priority: .utility) {
    let format = try #require(
      AVAudioFormat(
        standardFormatWithSampleRate: Double(MeetingAudioTimeline.sampleRate), channels: 1))
    func read(_ path: String) throws -> [Float] {
      let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
      let input = try #require(
        AVAudioPCMBuffer(
          pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
      try file.read(into: input)
      let buffer = try SpeechBufferConverter(format: format).convert(input)
      return Array(
        UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    }
    let far = try read(farPath)
    let near = try read(nearPath)
    let rate = MeetingAudioTimeline.sampleRate
    let samples = rate * 24
    let nearStart = rate * 16
    let delay = rate / 20
    let reference = (0..<samples).map { far[$0 % far.count] }
    let microphone = (0..<samples).map { index -> Float in
      let echo: Float = index >= delay ? reference[index - delay] * 0.6 : 0
      let voice: Float =
        index >= nearStart && index - nearStart < near.count ? near[index - nearStart] : 0
      return echo + voice
    }
    let processor = try MeetingAudioProcessor()
    let destination = FileManager.default.temporaryDirectory.appendingPathComponent(
      "sillies-echo-\(UUID().uuidString).m4a")
    defer { removeTestFile(at: destination) }
    let writer = try AudioRecordingWriter(destination: destination)
    func consume(_ output: MeetingAudioProcessor.Output) throws {
      activeChannels[0].append(output.meeting)
      activeChannels[1].append(output.microphone)
      try writer.append(output.recording)
    }
    for start in stride(from: 0, to: samples, by: MeetingAudioTimeline.frameSamples) {
      let time = 100 + Double(start) / Double(rate)
      for source in SessionAudioSource.allCases {
        let buffer = try #require(
          AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(MeetingAudioTimeline.frameSamples)))
        buffer.frameLength = buffer.frameCapacity
        let data = source == .application ? reference : microphone
        for offset in 0..<MeetingAudioTimeline.frameSamples {
          buffer.floatChannelData![0][offset] = data[start + offset]
        }
        try processor.append(buffer, source: source, at: time)
      }
      while let output = try processor.nextReadyOutput() { try consume(output) }
      try await Task.sleep(for: .milliseconds(10))
    }
    while let output = try processor.nextFinalOutput() { try consume(output) }
    _ = try writer.finish()
    let saved = try AVAudioFile(forReading: destination)
    #expect(abs(Double(saved.length) / saved.processingFormat.sampleRate - 24) < 0.1)
    for channel in activeChannels {
      await withCheckedContinuation { continuation in channel.finish { continuation.resume() } }
    }
  }
  try windowDragSmoothnessBudgetAndSinglePassPlacement()
  try windowResizeSmoothnessBudgetAndCompactionQuantization()
  try windowSwitchSmoothnessBudgetAndZeroFlickerAppTransition()
  try companionDragSmoothnessBudgetAndUnclippedMaskStability(characterID: "pogo")
  try await task.value
  let meeting = outputs[0].snapshot
  let microphone = outputs[1].snapshot
  print("ECHO MEETING TRANSCRIPT: \(meeting.0)")
  print("ECHO MICROPHONE TRANSCRIPT: \(microphone.0)")
  #expect(meeting.1.isEmpty && microphone.1.isEmpty)
  #expect(meeting.0.localizedCaseInsensitiveContains("report"))
  #expect(microphone.0.localizedCaseInsensitiveContains("customer"))
  #expect(microphone.0.localizedCaseInsensitiveContains("deadline"))
  #expect(!microphone.0.localizedCaseInsensitiveContains("report"))
  #expect(!microphone.0.localizedCaseInsensitiveContains("Alex"))
}
