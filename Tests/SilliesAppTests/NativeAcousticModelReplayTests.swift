import AVFoundation
import CoreML
import CryptoKit
import FluidAudio
import Foundation
import SilliesCore
import SilliesSpeech
import Testing

/// File-only research probe; neither model loading nor classification can download or capture audio.
@Test(.enabled(if: ProcessInfo.processInfo.environment["SILLIES_NEURAL_ACOUSTIC_REPLAY"] != nil))
func nativeAcousticModelReplayMatchesPublicFixtures() async throws {
  let path = try #require(ProcessInfo.processInfo.environment["SILLIES_NEURAL_ACOUSTIC_REPLAY"])
  try await NativeAcousticModelReplay.run(URL(fileURLWithPath: path))
}

private enum NativeAcousticModelReplay {
  private static let maximumManifestBytes = 256 * 1_024
  private static let maximumAudioBytes = 1_024 * 1_024
  private static let maximumFixtures = 128
  private static let maximumSamples = SpeechWindowConfiguration.maximumSampleCount

  private struct Fixture: Decodable {
    let id: String
    let audio: URL
    let sha256: String
    let expectedSpeech: Bool
  }
  private struct Request: Decodable {
    let modelDirectory: URL
    let fixtures: [Fixture]
    let output: URL
  }
  private enum Analysis: String, CaseIterable, Encodable {
    case captured, detectorGain

    func samples(from captured: [Float]) throws -> [Float] {
      guard self == .detectorGain else { return captured }
      var normalization = SpeechSignalNormalization(gain: .init(purpose: .detection))
      return try normalization.prepare(captured).apply(to: captured)
    }
  }
  private struct Result: Encodable {
    let id: String
    let analysis: Analysis
    let maximumProbability: Float
    let activeChunks: Int
    let totalChunks: Int
    let expectedSpeech: Bool
  }

  @concurrent static func run(_ url: URL) async throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    let request = try readRequest(url)
    let detector = try loadDetector(request.modelDirectory)
    let results = try await replay(request.fixtures, detector: detector)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(results).write(to: request.output, options: .atomic)
  }

  private static func readRequest(_ url: URL) throws -> Request {
    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    try #require((1...maximumManifestBytes).contains(size))
    let request = try JSONDecoder().decode(Request.self, from: Data(contentsOf: url))
    try #require(request.modelDirectory.isFileURL && request.output.isFileURL)
    try #require(!FileManager.default.fileExists(atPath: request.output.path))
    try #require((1...maximumFixtures).contains(request.fixtures.count))
    return request
  }

  private static func loadDetector(_ directory: URL) throws -> VadManager {
    let configuration = MLModelConfiguration()
    configuration.computeUnits = .cpuOnly
    let model = try MLModel(contentsOf: directory, configuration: configuration)
    return VadManager(config: .init(computeUnits: .cpuOnly), vadModel: model)
  }

  private static func replay(_ fixtures: [Fixture], detector: VadManager) async throws -> [Result] {
    var results: [Result] = []
    for fixture in fixtures {
      try Task.checkCancellation()
      let samples = try read(fixture)
      for analysis in Analysis.allCases {
        let values = try analysis.samples(from: samples)
        let chunks = try await detector.process(values)
        try Task.checkCancellation()
        try #require(!chunks.isEmpty && chunks.count <= maximumSamples / VadManager.chunkSize + 1)
        try #require(
          chunks.allSatisfy { $0.probability.isFinite && (0...1).contains($0.probability) })
        let active = chunks.filter(\.isVoiceActive).count
        results.append(
          .init(
            id: fixture.id, analysis: analysis,
            maximumProbability: chunks.map(\.probability).max() ?? 0,
            activeChunks: active, totalChunks: chunks.count,
            expectedSpeech: fixture.expectedSpeech))
        #expect(
          (active > 0) == fixture.expectedSpeech, "Acoustic fixture: \(fixture.id), \(analysis)")
      }
    }
    return results
  }

  private static func read(_ fixture: Fixture) throws -> [Float] {
    try #require(fixture.audio.isFileURL)
    let size = try fixture.audio.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    try #require((1...maximumAudioBytes).contains(size))
    let data = try Data(contentsOf: fixture.audio)
    try #require(
      SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == fixture.sha256)
    let audio = try AVAudioFile(forReading: fixture.audio)
    try #require(
      audio.processingFormat.sampleRate == SpeechWindowConfiguration.sampleRate
        && audio.processingFormat.channelCount == 1)
    try #require(audio.length > 0 && audio.length <= maximumSamples)
    let count = try #require(AVAudioFrameCount(exactly: audio.length))
    let buffer = try #require(
      AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: count))
    try audio.read(into: buffer)
    let values = try #require(buffer.floatChannelData?[0])
    let samples = Array(UnsafeBufferPointer(start: values, count: Int(buffer.frameLength)))
    try #require(samples.allSatisfy { $0.isFinite && abs($0) <= 1 })
    return samples
  }
}
