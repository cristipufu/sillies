import AVFoundation
@preconcurrency import CoreML
import FluidAudio
import Foundation
import SilliesSpeech

/// One decoder per audio source. The shared speech channel bounds each utterance and owns cancellation.
actor NemotronStreamingEngine: ReusableSpeechEngine {
  nonisolated private let executor = SpeechWorkerExecutor()
  nonisolated var unownedExecutor: UnownedSerialExecutor { executor.asUnownedSerialExecutor() }
  private static let sampleRate = 16_000.0
  private static let leftFrames = 70
  private static let chunkFrames = 7
  private static let rightFrames = 7
  private var manager: StreamingUnifiedAsrManager?
  private var progress = SpeechIncrementalWindow()
  private var timings: [TokenTiming] = []

  isolated deinit { dispatchPrecondition(condition: .notOnQueue(.main)) }

  func load(_ directory: URL, language: SpeechLanguage) async throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    try Task.checkCancellation()
    let code =
      language.isAutomatic
      ? "auto" : language.locale.language.languageCode?.identifier ?? language.id
    guard let prompt = NemotronUnifiedLanguage(rawValue: code) else {
      throw SpeechError.unavailable(
        String(localized: "Nemotron Unified ASR does not support this language."))
    }
    let configuration = MLModelConfiguration()
    configuration.computeUnits = .cpuAndNeuralEngine
    let manager = StreamingUnifiedAsrManager(
      configuration: configuration,
      config: UnifiedConfig(
        leftFrames: Self.leftFrames, chunkFrames: Self.chunkFrames, rightFrames: Self.rightFrames,
        family: .nemotronMultilingual(prompt)), encoderPrecision: .fp16)
    try await manager.loadModels(from: directory)
    try Task.checkCancellation()
    self.manager = manager
  }

  func transcribe(_ request: SpeechWindowRequest) async throws -> SpeechWindowResult {
    dispatchPrecondition(condition: .notOnQueue(.main))
    try Task.checkCancellation()
    guard let manager else {
      throw SpeechError.unavailable(String(localized: "The speech model is not ready."))
    }
    let update = progress.advance(request)
    if update.action == .restart {
      try await manager.reset()
      timings.removeAll(keepingCapacity: true)
    }
    if !update.samples.isEmpty {
      try await manager.appendAudio(Self.audioBuffer(update.samples))
    }
    switch update.phase {
    case .partial: try await manager.processBufferedAudio()
    case .complete: _ = try await manager.finish()
    }
    try Task.checkCancellation()
    timings.append(contentsOf: await manager.consumeTokenTimings())
    return SpeechWindowResult(
      words: buildWordTimings(from: timings).map {
        SpeechWord(text: $0.word, start: $0.startTime, end: $0.endTime)
      })
  }

  func resetForReuse() async throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    try await manager?.reset()
    progress = SpeechIncrementalWindow()
    timings.removeAll(keepingCapacity: true)
  }

  private static func audioBuffer(_ samples: [Float]) throws -> AVAudioPCMBuffer {
    guard let count = AVAudioFrameCount(exactly: samples.count),
      let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count),
      let destination = buffer.floatChannelData?[0]
    else {
      throw SpeechError.unavailable(String(localized: "Could not prepare streaming speech audio."))
    }
    buffer.frameLength = count
    samples.withUnsafeBufferPointer { source in
      if let base = source.baseAddress { destination.update(from: base, count: samples.count) }
    }
    return buffer
  }
}
