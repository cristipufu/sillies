import AVFoundation
@preconcurrency import CoreML
import FluidAudio
import Foundation
import SilliesSpeech

/// Owns native models, PCM conversion and token timing accumulation for one source.
actor NemotronNativeDecoder: NemotronDecoding {
  private static let sampleRate = 16_000.0
  private let manager: StreamingUnifiedAsrManager
  private var timings: [TokenTiming] = []
  private init(manager: StreamingUnifiedAsrManager) { self.manager = manager }

  static func load(_ directory: URL, language: SpeechLanguage) async throws -> NemotronNativeDecoder
  {
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
      config: NemotronRecognitionConfiguration.native(language: prompt), encoderPrecision: .fp16)
    try await manager.loadModels(from: directory)
    try Task.checkCancellation()
    return NemotronNativeDecoder(manager: manager)
  }

  func decode(_ samples: [Float], phase: SpeechWindowPosition.Phase) async throws
    -> SpeechWindowResult
  {
    if !samples.isEmpty { try await manager.appendAudio(Self.audioBuffer(samples)) }
    switch phase {
    case .partial, .boundary: try await manager.processBufferedAudio()
    case .complete: _ = try await manager.finish()
    }
    try Task.checkCancellation()
    timings.append(contentsOf: await manager.consumeTokenTimings())
    return SpeechWindowResult(
      words: buildWordTimings(from: timings).map {
        SpeechWord(text: $0.word, start: $0.startTime, end: $0.endTime)
      })
  }

  func reset() async throws {
    timings.removeAll(keepingCapacity: true)
    try await manager.reset()
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
