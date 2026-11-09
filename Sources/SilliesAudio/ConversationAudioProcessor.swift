import AVFoundation
import Foundation
import SilliesCore

/// Reuses the meeting clock alignment and AEC3, substituting actual app playback for system capture.
final class ConversationAudioProcessor {
  private let reference: VoicePlaybackReference
  private let audio: MeetingAudioProcessor
  private let detector: VoiceActivityDetector
  private var microphoneEnd: TimeInterval?
  private var acousticWindow = VoiceAcousticWindow()
  private var delivery = VoiceAcousticEvidence.Delivery()
  private var lastReferenceEnd: TimeInterval?
  private var processedEnd: TimeInterval?
  var lastSpeechSample: TimeInterval? { detector.lastSpeechSample }

  init(reference: VoicePlaybackReference) throws {
    self.reference = reference
    audio = try MeetingAudioProcessor()
    detector = try VoiceActivityDetector()
  }

  func append(_ packet: AudioCaptureInputQueue.Packet) throws {
    guard let microphone = AudioPCMTools.buffer(from: packet.sample) else { return }
    try appendMicrophone(microphone, at: packet.sampleStartTime)
  }

  func appendMicrophone(_ microphone: AVAudioPCMBuffer, at time: TimeInterval) throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    // Reference callbacks can precede device playback by output latency. The timeline holds both sources.
    let batch = reference.drain()
    delivery.droppedReferenceFrames = adding(delivery.droppedReferenceFrames, batch.droppedFrames)
    delivery.rejectedReferenceFrames = adding(
      delivery.rejectedReferenceFrames, batch.rejectedFrames)
    for frame in batch.frames {
      let end = frame.startTime + Double(frame.samples.count) / frame.sampleRate
      lastReferenceEnd = max(lastReferenceEnd ?? end, end)
      guard
        end >= time - MeetingAudioTimeline.callbackHoldback
      else {
        delivery.staleReferenceFrames = adding(delivery.staleReferenceFrames, 1)
        continue
      }
      try audio.append(Self.buffer(frame), source: .application, at: frame.startTime)
    }
    try audio.append(microphone, source: .microphone, at: time)
    microphoneEnd = time + Double(microphone.frameLength) / microphone.format.sampleRate
  }

  func next() throws -> (AVAudioPCMBuffer, VoiceTurnEndpoint.Event?, TimeInterval)? {
    dispatchPrecondition(condition: .notOnQueue(.main))
    guard let microphoneEnd = audio.microphoneEndTime,
      let output = try audio.nextReadyOutput(
        through: microphoneEnd - MeetingAudioTimeline.callbackHoldback)
    else { return nil }
    acousticWindow.append(output.acoustics)
    processedEnd = output.endTime
    return (
      output.microphone, try detector.consume(output.microphone, endingAt: output.endTime),
      output.endTime
    )
  }

  func nextFinalMicrophone() throws -> AVAudioPCMBuffer? {
    dispatchPrecondition(condition: .notOnQueue(.main))
    guard let microphoneEnd, let output = try audio.nextFinalOutput() else { return nil }
    let buffer = output.microphone
    let start = output.endTime - Double(buffer.frameLength) / buffer.format.sampleRate
    let remaining = ((microphoneEnd - start) * buffer.format.sampleRate).rounded()
    guard remaining > 0 else { return nil }
    if remaining < Double(buffer.frameLength), let length = AVAudioFrameCount(exactly: remaining) {
      buffer.frameLength = length
    }
    return output.microphone
  }

  func beginNextTurn() { detector.beginNextTurn() }

  func assessment(at boundary: VoiceAcousticEvidence.Boundary) -> VoiceAcousticEvidence {
    delivery.referenceDiscontinuities = audio.referenceDiscontinuities
    delivery.microphoneDiscontinuities = audio.microphoneDiscontinuities
    if let processedEnd, let lastReferenceEnd {
      delivery.referenceAgeMilliseconds = (processedEnd - lastReferenceEnd) * 1_000
    }
    return .init(
      boundary: boundary, window: acousticWindow.snapshot, delivery: delivery,
      echo: audio.echoStatistics())
  }

  private func adding(_ count: Int, _ increment: Int) -> Int {
    let sum = count.addingReportingOverflow(increment)
    return sum.overflow ? Int.max : sum.partialValue
  }

  private static func buffer(_ frame: AudioRenderFrame) throws -> AVAudioPCMBuffer {
    guard let count = AVAudioFrameCount(exactly: frame.samples.count),
      let format = AVAudioFormat(standardFormatWithSampleRate: frame.sampleRate, channels: 1),
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count),
      let destination = buffer.floatChannelData?[0]
    else {
      throw AudioCaptureFailure.unavailable(
        String(localized: "Could not prepare the playback echo reference."))
    }
    buffer.frameLength = count
    frame.samples.withUnsafeBufferPointer { source in
      if let base = source.baseAddress {
        destination.update(from: base, count: frame.samples.count)
      }
    }
    return buffer
  }
}
