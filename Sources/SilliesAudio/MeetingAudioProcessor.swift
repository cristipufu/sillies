import AVFoundation
import SilliesCore
import SilliesSpeech

/// Aligns both sources before AEC. The speaker reference is never sent to a playback device.
final class MeetingAudioProcessor {
  struct Output {
    let meeting: AVAudioPCMBuffer
    let microphone: AVAudioPCMBuffer
    let recording: AVAudioPCMBuffer
    let endTime: TimeInterval
  }
  private static let channelCount: AVAudioChannelCount = 1
  private static let mixGain: Float = 0.5
  private let format: AVAudioFormat
  private let meetingConverter: SpeechBufferConverter
  private let microphoneConverter: SpeechBufferConverter
  private let canceller: MeetingEchoCanceller
  private var timeline = MeetingAudioTimeline()

  init() throws {
    guard
      let format = AVAudioFormat(
        standardFormatWithSampleRate: Double(MeetingAudioTimeline.sampleRate),
        channels: Self.channelCount)
    else { throw AudioCaptureFailure.unavailable("Could not prepare meeting audio.") }
    self.format = format
    meetingConverter = SpeechBufferConverter(format: format)
    microphoneConverter = SpeechBufferConverter(format: format)
    canceller = try MeetingEchoCanceller()
  }

  func append(_ buffer: AVAudioPCMBuffer, source: SessionAudioSource, at time: TimeInterval) throws
  {
    let converter = source == .application ? meetingConverter : microphoneConverter
    let converted = try converter.convert(buffer)
    guard let data = converted.floatChannelData?[0], converted.frameLength > 0 else { return }
    let samples = Array(UnsafeBufferPointer(start: data, count: Int(converted.frameLength)))
    do {
      try timeline.append(
        samples, source: source == .application ? .meeting : .microphone, at: time)
    } catch {
      throw AudioCaptureFailure.unavailable(
        "Meeting audio timing changed unexpectedly. Finish to save the available recording and transcript."
      )
    }
  }

  func nextReadyOutput() throws -> Output? {
    try timeline.nextReadyFrame().map(process)
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
      endTime: frame.startTime + Double(frame.validSamples) / format.sampleRate)
  }

  private func buffer(_ samples: [Float], count: Int) throws -> AVAudioPCMBuffer {
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
      let data = buffer.floatChannelData?[0]
    else { throw AudioCaptureFailure.unavailable("Could not prepare processed meeting audio.") }
    buffer.frameLength = AVAudioFrameCount(count)
    samples.withUnsafeBufferPointer { data.update(from: $0.baseAddress!, count: count) }
    return buffer
  }
}
