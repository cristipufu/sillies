import AVFoundation
import Foundation
import SilliesCore

/// Aligns both sources before AEC. The speaker reference is never sent to a playback device.
final class MeetingAudioProcessor {
  struct Output {
    let meeting: AVAudioPCMBuffer
    let microphone: AVAudioPCMBuffer
    let recording: AVAudioPCMBuffer
    let endTime: TimeInterval
    let acoustics: VoiceAcousticWindow.Frame
  }
  private static let channelCount: AVAudioChannelCount = 1
  private static let mixGain: Float = 0.5
  private static let fullScaleMagnitude: Float = 1
  private let format: AVAudioFormat
  private let meetingConverter: MeetingAudioResampler
  private let microphoneConverter: MeetingAudioResampler
  private let canceller: MeetingEchoCanceller
  private var timeline = MeetingAudioTimeline()

  init() throws {
    guard
      let format = AVAudioFormat(
        standardFormatWithSampleRate: Double(MeetingAudioTimeline.sampleRate),
        channels: Self.channelCount)
    else {
      throw AudioCaptureFailure.unavailable(String(localized: "Could not prepare meeting audio."))
    }
    self.format = format
    meetingConverter = MeetingAudioResampler(format: format)
    microphoneConverter = MeetingAudioResampler(format: format)
    canceller = try MeetingEchoCanceller()
  }

  func append(_ buffer: AVAudioPCMBuffer, source: SessionAudioSource, at time: TimeInterval) throws
  {
    let converter = source == .application ? meetingConverter : microphoneConverter
    do {
      let output = try converter.convert(buffer, at: time)
      let converted = output.buffer
      guard let data = converted.floatChannelData?[0], converted.frameLength > 0 else { return }
      let samples = Array(UnsafeBufferPointer(start: data, count: Int(converted.frameLength)))
      try timeline.append(
        samples, source: source == .application ? .meeting : .microphone, at: output.startTime)
    } catch is MeetingAudioTimeline.Failure {
      throw Self.timingFailure()
    }
  }

  var microphoneEndTime: TimeInterval? { microphoneConverter.outputEndTime }
  var referenceDiscontinuities: Int { meetingConverter.discontinuities }
  var microphoneDiscontinuities: Int { microphoneConverter.discontinuities }
  func echoStatistics() -> VoiceAcousticEvidence.Echo { canceller.statistics() }

  private static func timingFailure() -> AudioCaptureFailure {
    AudioCaptureFailure.unavailable(
      String(
        localized:
          "Meeting audio timing changed unexpectedly. Finish to save the available recording and transcript."
      )
    )
  }

  func nextReadyOutput() throws -> Output? {
    try timeline.nextReadyFrame().map(process)
  }

  func nextReadyOutput(through time: TimeInterval) throws -> Output? {
    try timeline.nextReadyFrame(through: time).map(process)
  }

  func nextFinalOutput() throws -> Output? {
    try timeline.nextFinalFrame().map(process)
  }

  func reset() throws {
    timeline = MeetingAudioTimeline()
    meetingConverter.reset()
    microphoneConverter.reset()
    try canceller.reset()
  }

  private func process(_ frame: MeetingAudioTimeline.Frame) throws -> Output {
    let cleaned = try canceller.process(reference: frame.meeting, microphone: frame.microphone)
    let mixed = zip(frame.meeting, cleaned).map { ($0 + $1) * Self.mixGain }
    return try Output(
      meeting: buffer(frame.meeting, count: frame.validSamples),
      microphone: buffer(cleaned, count: frame.validSamples),
      recording: buffer(mixed, count: frame.validSamples),
      endTime: frame.startTime + Double(frame.validSamples) / format.sampleRate,
      acoustics: .init(
        referenceSamples: frame.meetingSamplesPresent,
        clippedSamples: frame.microphone.count { abs($0) >= Self.fullScaleMagnitude },
        power: .init(
          reference: power(frame.meeting), microphone: power(frame.microphone),
          cleaned: power(cleaned))))
  }

  private func power(_ samples: [Float]) -> Double {
    samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count)
  }

  private func buffer(_ samples: [Float], count: Int) throws -> AVAudioPCMBuffer {
    guard count > 0, count <= samples.count, let capacity = AVAudioFrameCount(exactly: count),
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity),
      let data = buffer.floatChannelData?[0]
    else {
      throw AudioCaptureFailure.unavailable(
        String(localized: "Could not prepare processed meeting audio."))
    }
    buffer.frameLength = capacity
    try samples.withUnsafeBufferPointer { samples in
      guard let source = samples.baseAddress else {
        throw AudioCaptureFailure.unavailable(
          String(localized: "Processed meeting audio is empty."))
      }
      data.update(from: source, count: count)
    }
    return buffer
  }
}
