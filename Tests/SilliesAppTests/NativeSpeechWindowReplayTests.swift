import AVFoundation
import CryptoKit
import Foundation
import SilliesSpeech
import Testing
import WhisperKit

@testable import SilliesSpeechNemotron
@testable import SilliesSpeechWhisper

/// Explicit file-only native replay. The caller supplies public research inputs, never live audio.
@Test(.enabled(if: ProcessInfo.processInfo.environment["SILLIES_SPEECH_WINDOW_REPLAY"] != nil))
func nativeSpeechWindowReplayPreservesDecoderResults() async throws {
  let path = try #require(ProcessInfo.processInfo.environment["SILLIES_SPEECH_WINDOW_REPLAY"])
  try await NativeSpeechWindowReplay.run(URL(fileURLWithPath: path))
}

private enum NativeSpeechWindowReplay {
  private enum Provider: String, Decodable { case nemotron, whisper }
  private struct PreparedEngine {
    let transcribe: @Sendable (SpeechWindowRequest) async throws -> WindowResult
    let reset: @Sendable () async throws -> Void
  }
  private static let sampleRate = 16_000.0
  private static let maximumAudioSamples = 384_000
  private static let maximumWindows = 128
  private static let maximumWordsPerWindow = 1_024
  private static let maximumManifestBytes = 256 * 1_024
  private static let maximumAudioBytes = 8 * 1_024 * 1_024
  private struct Request: Decodable {
    struct Window: Codable {
      let start: Double
      let sampleCount: Int
      let phase: SpeechWindowPosition.Phase
    }
    let audio: URL
    let audioSHA256: String
    let modelDirectory: URL
    let language: String
    let gain: Float?
    let signalMode: SpeechSignalNormalization.Mode?
    let provider: Provider?
    let windows: [Window]
    let output: URL
  }
  private struct Word: Encodable {
    let text: String
    let start: Double
    let end: Double
    var probability: Float?
  }
  private struct Segment: Encodable {
    let text: String
    let start: Float
    let end: Float
    let averageLogProbability: Float
    let compressionRatio: Float
    let noSpeechProbability: Float
    let temperature: Float
  }
  private struct WindowResult: Sendable {
    let words: [Word]
    var segments: [Segment] = []
    var nativeDecodingWindows: Double?
  }
  private struct Result: Encodable {
    let window: Request.Window
    let words: [Word]
    let segments: [Segment]
    let nativeDecodingWindows: Double?
  }

  static func run(_ url: URL) async throws {
    try #require(
      try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0 <= maximumManifestBytes)
    let request = try JSONDecoder().decode(Request.self, from: Data(contentsOf: url))
    try #require(
      request.audio.isFileURL && request.modelDirectory.isFileURL && request.output.isFileURL)
    try #require(!FileManager.default.fileExists(atPath: request.output.path))
    try #require(
      try request.audio.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0 <= maximumAudioBytes)
    let bytes = try Data(contentsOf: request.audio)
    try #require(
      SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() == request.audioSHA256)
    let gain = request.gain ?? 1
    try #require(gain.isFinite && gain >= 1 && gain <= 16)
    let samples = try readAudio(request.audio).map { $0 * gain }
    try #require(samples.allSatisfy { $0.isFinite && abs($0) <= 1 })
    try #require((1...maximumWindows).contains(request.windows.count))
    let language = SpeechLanguage(id: request.language, name: request.language, isInstalled: true)
    let prepared = try await prepare(request, language: language)
    var results: [Result] = []
    for window in request.windows {
      try #require(
        window.start.isFinite && window.start >= 0
          && window.start <= Double(samples.count) / sampleRate)
      let start = Int((window.start * sampleRate).rounded())
      try #require(start <= samples.count && window.sampleCount > 0)
      try #require(window.sampleCount <= samples.count - start)
      var input = SpeechWindowRequest(
        samples: Array(samples[start..<(start + window.sampleCount)]), language: language)
      input.window = .init(start: window.start, phase: window.phase)
      let result = try await prepared.transcribe(input)
      try #require(result.words.count <= maximumWordsPerWindow)
      try #require(result.segments.count <= maximumWordsPerWindow)
      results.append(
        .init(
          window: window, words: result.words, segments: result.segments,
          nativeDecodingWindows: result.nativeDecodingWindows))
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(results).write(to: request.output, options: .atomic)
    try await prepared.reset()
  }

  private static func prepare(_ request: Request, language: SpeechLanguage) async throws
    -> PreparedEngine
  {
    switch request.provider ?? .nemotron {
    case .nemotron:
      let decoder = try await NemotronNativeDecoder.load(request.modelDirectory, language: language)
      let engine = NemotronStreamingEngine(
        decoder: decoder, normalization: .init(mode: request.signalMode ?? .preserve))
      return .init(
        transcribe: { input in
          let result = try await engine.transcribe(input)
          return .init(
            words: result.words.map { .init(text: $0.text, start: $0.start, end: $0.end) })
        }, reset: { try await engine.resetForReuse() })
    case .whisper:
      let engine = WhisperWindowEngine()
      try await engine.load(request.modelDirectory)
      return .init(
        transcribe: { input in
          let outcome = try await engine.decodeWindow(input)
          let segments = outcome.nativeResults.flatMap(\.segments)
          return .init(
            words: outcome.acceptedSegments.flatMap { $0.words ?? [] }.map {
              .init(
                text: $0.word.trimmingCharacters(in: .whitespaces), start: Double($0.start),
                end: Double($0.end), probability: $0.probability)
            },
            segments: segments.map {
              .init(
                text: $0.text, start: $0.start, end: $0.end,
                averageLogProbability: $0.avgLogprob, compressionRatio: $0.compressionRatio,
                noSpeechProbability: $0.noSpeechProb, temperature: $0.temperature)
            },
            nativeDecodingWindows: outcome.nativeResults.reduce(0) {
              $0 + $1.timings.totalDecodingWindows
            })
        }, reset: {})
    }
  }

  private static func readAudio(_ url: URL) throws -> [Float] {
    let file = try AVAudioFile(forReading: url)
    try #require(
      file.processingFormat.sampleRate == sampleRate && file.processingFormat.channelCount == 1)
    try #require(file.length > 0 && file.length <= maximumAudioSamples)
    let count = try #require(AVAudioFrameCount(exactly: file.length))
    let buffer = try #require(
      AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: count))
    try file.read(into: buffer)
    let samples = try #require(buffer.floatChannelData?[0])
    return Array(UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength)))
  }
}
