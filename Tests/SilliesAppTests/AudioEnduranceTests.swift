import AVFoundation
import AppKit
import SilliesAudioTestSupport
import SilliesCore
import SwiftUI
import Testing

@testable import SilliesApp
@testable import SilliesAudio

@Test(.enabled(if: ProcessInfo.processInfo.environment["SILLIES_LONG_AUDIO_CHECK"] == "1"))
@MainActor func sustainedAudioEncodingKeepsTranscriptScrollingResponsive() async throws {
  let destination = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sillies-endurance-\(UUID().uuidString).m4a")
  defer { removeTestFile(at: destination) }
  let model = AudioSessionPresentation(kind: .participate, sourceLabel: "Synthetic endurance check")
  model.phase = .capturing
  model.isLoadingLanguages = false
  model.languages = [fixtureEnglish]
  model.selectedLanguageID = fixtureEnglish.id
  model.followsLiveTranscript = true
  let window = AudioSessionWindowController()
  defer { window.close() }
  window.show(model)
  let delivery = AudioSessionUpdateDelivery {
    if case .transcript(let text, let level, let elapsed) = $0 {
      model.transcript = text
      model.audioLevel = level
      model.elapsed = elapsed
    }
  }
  defer { delivery.stop() }
  let progress = EnduranceProgress()
  let worker = Task.detached(priority: .utility) {
    defer { progress.complete() }
    return try AudioEnduranceWorker(destination: destination, delivery: delivery).run()
  }
  defer { worker.cancel() }
  let deadline = ContinuousClock.now.advanced(by: .seconds(60))
  var scrollSamples: [Duration] = []
  while !progress.isFinished && ContinuousClock.now < deadline {
    if let view = window.window?.contentView, let duration = measureEnduranceScroll(in: view) {
      scrollSamples.append(duration)
    }
    try await Task.sleep(for: .milliseconds(8))
  }
  if !progress.isFinished { worker.cancel() }
  let result = try await worker.value
  #expect(result.duration == Double(AudioEnduranceWorker.durationSeconds))
  #expect(result.transcript.contains("History passage 0."))
  #expect(result.transcript.contains("Live passage 599."))
  #expect(scrollSamples.count > 10)
  scrollSamples.sort()
  let p95 = scrollSamples[Int(Double(scrollSamples.count) * 0.95)]
  #expect(p95 < .milliseconds(16))
  print(
    "ENDURANCE: encoded \(result.duration) seconds with four hours of transcript history; scroll p95 \(p95)."
  )
}

@MainActor private func measureEnduranceScroll(in view: NSView) -> Duration? {
  let start = ContinuousClock.now
  view.layoutSubtreeIfNeeded()
  guard let scroll = findTranscriptScrollView(in: view) else { return nil }
  let maximumOffset = max(0, scroll.textView.bounds.height - scroll.contentView.bounds.height)
  let nextOffset = scroll.contentView.bounds.origin.y < maximumOffset / 2 ? maximumOffset : 0
  scroll.contentView.scroll(to: CGPoint(x: 0, y: nextOffset))
  scroll.reflectScrolledClipView(scroll.contentView)
  view.displayIfNeeded()
  return ContinuousClock.now - start
}

private final class EnduranceProgress: @unchecked Sendable {
  private let lock = NSLock()
  private var finished = false
  var isFinished: Bool { lock.withLock { finished } }
  func complete() { lock.withLock { finished = true } }
}

/// Exercises the real synchronization, echo canceller and encoder without capturing any device.
private final class AudioEnduranceWorker {
  static let durationSeconds = 600
  private static let framesPerSecond = 100
  private static let historyHours = 4
  private static let secondsPerHour = 3_600
  private static let historyPassageSeconds = 2
  private static let sampleOrigin: TimeInterval = 100
  private static let signalAmplitude: Float = 0.05
  private static let signalPeriodSamples = 80
  private let delivery: AudioSessionUpdateDelivery
  private let processor: MeetingAudioProcessor
  private let writer: AudioRecordingWriter
  private let reference: AVAudioPCMBuffer
  private let microphone: AVAudioPCMBuffer
  private var transcript = TranscriptTimeline()

  init(destination: URL, delivery: AudioSessionUpdateDelivery) throws {
    self.delivery = delivery
    processor = try MeetingAudioProcessor()
    writer = try AudioRecordingWriter(destination: destination)
    let format = try #require(
      AVAudioFormat(
        standardFormatWithSampleRate: Double(MeetingAudioTimeline.sampleRate), channels: 1))
    reference = try Self.makeBuffer(format)
    microphone = try Self.makeBuffer(format)
    for sample in 0..<MeetingAudioTimeline.frameSamples {
      reference.floatChannelData![0][sample] =
        sin(Float(sample) * 2 * .pi / Float(Self.signalPeriodSamples)) * Self.signalAmplitude
    }
    seedHistory()
  }

  func run() throws -> AudioCaptureResult {
    for second in 0..<Self.durationSeconds {
      try Task.checkCancellation()
      try autoreleasepool {
        for frame in 0..<Self.framesPerSecond { try processFrame(second: second, frame: frame) }
        publishPassage(second)
      }
    }
    while let output = try processor.nextFinalOutput() { try writer.append(output.recording) }
    let url = try writer.finish()
    let saved = try AVAudioFile(forReading: #require(url))
    let duration = Double(saved.length) / saved.processingFormat.sampleRate
    #expect(abs(duration - Double(Self.durationSeconds)) < 0.1)
    return AudioCaptureResult(
      transcript: transcript.text, recordingURL: url,
      duration: Double(Self.durationSeconds), failure: nil)
  }

  private func processFrame(second: Int, frame: Int) throws {
    let time = Self.sampleOrigin + Double(second) + Double(frame) / Double(Self.framesPerSecond)
    try processor.append(reference, source: .application, at: time)
    try processor.append(microphone, source: .microphone, at: time)
    while let output = try processor.nextReadyOutput() { try writer.append(output.recording) }
  }

  private func seedHistory() {
    let count = Self.historyHours * Self.secondsPerHour / Self.historyPassageSeconds
    for index in 0..<count {
      let start = Double(index * Self.historyPassageSeconds)
      transcript.receive(
        .init(
          source: "Meeting", range: start..<(start + 1),
          text: "History passage \(index).", isFinal: true))
    }
  }

  private func publishPassage(_ second: Int) {
    let start = Double(Self.historyHours * Self.secondsPerHour + second)
    transcript.receive(
      .init(
        source: "Meeting", range: start..<(start + 1),
        text: "Live passage \(second). We will review the customer proposal on Friday.",
        isFinal: true))
    delivery.enqueue(
      .transcript(
        transcript.preview(characterLimit: 8_192), level: 0.2, elapsed: Double(second + 1)))
  }

  private static func makeBuffer(_ format: AVAudioFormat) throws -> AVAudioPCMBuffer {
    let buffer = try #require(
      AVAudioPCMBuffer(
        pcmFormat: format, frameCapacity: AVAudioFrameCount(MeetingAudioTimeline.frameSamples)))
    buffer.frameLength = buffer.frameCapacity
    buffer.floatChannelData![0].initialize(repeating: 0, count: Int(buffer.frameLength))
    return buffer
  }
}
