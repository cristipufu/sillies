import AVFoundation
import Foundation
import Testing

@testable import SilliesApp

@Test func speechChunksPreserveSamplesFromTinyStereoCallbacks() throws {
  let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 2))
  let chunker = SpeechAudioChunker(format: format)
  let callbackFrames = 23
  let callbackCount = 1_001
  var chunks: [AVAudioPCMBuffer] = []
  for callback in 0..<callbackCount {
    let buffer = try #require(
      AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(callbackFrames)))
    buffer.frameLength = buffer.frameCapacity
    let samples = try #require(buffer.floatChannelData)
    for channel in 0..<2 {
      for frame in 0..<callbackFrames {
        samples[channel][frame] = Float(callback * callbackFrames + frame + channel)
      }
    }
    chunks.append(contentsOf: try chunker.append(buffer))
  }
  #expect(chunks.count == 9)
  chunks.append(try #require(chunker.flush()))
  #expect(chunker.flush() == nil)
  var offset = 0
  for chunk in chunks {
    let samples = try #require(chunk.floatChannelData)
    for channel in 0..<2 {
      let actual = Array(
        UnsafeBufferPointer(start: samples[channel], count: Int(chunk.frameLength)))
      let expected = (0..<Int(chunk.frameLength)).map { Float(offset + $0 + channel) }
      #expect(actual == expected)
    }
    offset += Int(chunk.frameLength)
  }
  #expect(offset == callbackFrames * callbackCount)
  #expect(Double(SpeechAudioChunker.streamCapacity) * SpeechAudioChunker.chunkDuration >= 12)
}

@Test func languageSelectionUsesInstalledRememberedOrMatchingDeviceLanguage() {
  let missing = SpeechLanguage(
    id: "de-DE", name: "German", isInstalled: false, supportsNotes: true)
  let catalog = SpeechLanguageCatalog(languages: [fixtureEnglish, fixtureFrench, missing])
  #expect(catalog.preferredLanguage(savedIdentifier: "fr-FR") == fixtureFrench)
  #expect(
    catalog.preferredLanguage(savedIdentifier: nil, deviceLocale: Locale(identifier: "en_GB"))
      == fixtureEnglish)
  #expect(catalog.preferredLanguage(savedIdentifier: "de-DE") == nil)
  #expect(
    catalog.preferredLanguage(savedIdentifier: nil, deviceLocale: Locale(identifier: "ro_RO"))
      == nil)
}

@Test func languageSwitchPreservesBothDraftsAndBuffersNewSpeech() async throws {
  let harness = SpeechPipelineHarness()
  try await harness.start()
  try await harness.perform {
    let channels = harness.bank.channels
    channels[0].emit("Earlier meeting words", final: false)
    channels[1].emit("Earlier microphone words", final: false)
  }
  try await harness.perform {
    harness.pipeline.changeLanguage(fixtureFrench, elapsed: 5)
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 240))
    buffer.frameLength = 240
    harness.pipeline.append(buffer, source: .application, elapsed: 5.1)
    harness.pipeline.append(buffer, source: .microphone, elapsed: 5.1)
    for channel in harness.bank.channels { channel.complete() }
  }
  try await awaitSpeechCondition { harness.bank.channels.count == 4 }
  try await awaitSpeechCondition {
    harness.bank.channels.suffix(2).allSatisfy { $0.frameCount == 240 }
  }
  try await harness.perform {
    harness.bank.channels[0].emit("Stale old recognizer output", final: true)
    harness.bank.channels[2].emit("Bonjour réunion", final: true)
    harness.bank.channels[3].emit("Bonjour microphone", final: true)
  }
  let result = try await harness.perform { harness.pipeline.text }
  #expect(result.contains("Earlier meeting words"))
  #expect(result.contains("Earlier microphone words"))
  #expect(result.contains("Language: French"))
  #expect(result.contains("Bonjour réunion"))
  #expect(result.contains("Bonjour microphone"))
  #expect(!result.contains("Stale"))
  try await harness.perform { harness.pipeline.cancel() }
}

@Test func finishingDuringLanguageDrainCompletesOnceAndPreservesDrafts() async throws {
  let harness = SpeechPipelineHarness()
  try await harness.start()
  try await harness.perform { harness.bank.channels[0].emit("Keep this draft", final: false) }
  let notice: String? = await withCheckedContinuation { continuation in
    harness.queue.async {
      harness.pipeline.changeLanguage(fixtureFrench, elapsed: 2)
      harness.pipeline.finish { continuation.resume(returning: $0) }
      for channel in harness.bank.channels { channel.complete() }
    }
  }
  #expect(notice == nil)
  let result = try await harness.perform { harness.pipeline.text }
  #expect(result.contains("Keep this draft"))
  #expect(harness.bank.channels.count == 2)
}

@Test func endingDuringSpeechPreparationCancelsWithoutWaitingForTheModel() async throws {
  let harness = SpeechPipelineHarness()
  let result: Result<Void, Error> = await withCheckedContinuation { continuation in
    harness.queue.async {
      harness.pipeline.start(language: fixtureEnglish) { continuation.resume(returning: $0) }
      harness.pipeline.cancel()
    }
  }
  if case .success = result { Issue.record("A cancelled preparation must not start capture.") }
  try await Task.sleep(for: .milliseconds(20))
  #expect(harness.bank.channels.allSatisfy { $0.wasCancelled })
}

private final class SpeechPipelineHarness: @unchecked Sendable {
  let queue = DispatchQueue(label: "sillies.test.speech-pipeline")
  let bank = SpeechFixtureBank()
  let pipeline: SessionSpeechPipeline

  init() {
    let bank = bank
    pipeline = SessionSpeechPipeline(
      configuration: .init(
        sources: [.application, .microphone], queue: queue,
        makeChannel: { _, output, _ in bank.make(output: output) }
      ), onEvent: { _ in })
  }

  func start() async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      queue.async {
        self.pipeline.start(language: fixtureEnglish) { continuation.resume(with: $0) }
      }
    }
  }

  func perform<Value: Sendable>(_ action: @escaping @Sendable () throws -> Value) async throws
    -> Value
  {
    try await withCheckedThrowingContinuation { continuation in
      queue.async {
        do { continuation.resume(returning: try action()) } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }
}

private final class SpeechFixtureBank: @unchecked Sendable {
  private let lock = NSLock()
  private var created: [ControllableSpeechChannel] = []
  var channels: [ControllableSpeechChannel] { lock.withLock { created } }
  func make(output: @escaping LocalSpeechFactory.Output) -> ControllableSpeechChannel {
    let channel = ControllableSpeechChannel(output: output)
    lock.withLock { created.append(channel) }
    return channel
  }
}

private final class ControllableSpeechChannel: LocalSpeechChannel, @unchecked Sendable {
  private let lock = NSLock()
  private let output: LocalSpeechFactory.Output
  private var completion: (@Sendable () -> Void)?
  private var frames = 0
  private var cancelled = false
  init(output: @escaping LocalSpeechFactory.Output) { self.output = output }
  var frameCount: Int { lock.withLock { frames } }
  var wasCancelled: Bool { lock.withLock { cancelled } }
  func emit(_ text: String, final: Bool) { output(SpeechPhrase(text: text, isFinal: final)) }
  func append(_ buffer: AVAudioPCMBuffer) { lock.withLock { frames += Int(buffer.frameLength) } }
  func finish(completion: @escaping @Sendable () -> Void) {
    lock.withLock { self.completion = completion }
  }
  func cancel() {
    lock.withLock { cancelled = true }
    complete()
  }
  func complete() {
    let callback = lock.withLock {
      defer { completion = nil }
      return completion
    }
    callback?()
  }
}

private func awaitSpeechCondition(_ condition: @escaping @Sendable () -> Bool) async throws {
  let deadline = ContinuousClock.now.advanced(by: .seconds(2))
  while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
  #expect(condition())
}
