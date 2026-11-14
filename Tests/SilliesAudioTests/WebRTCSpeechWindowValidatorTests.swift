import AVFoundation
import CryptoKit
import Foundation
import SilliesSpeech
import Testing

@testable import SilliesAudio

@Test(.enabled(if: ProcessInfo.processInfo.environment["SILLIES_ACOUSTIC_REPLAY"] != nil))
func speechRecognitionNativeAcousticWindowsMatchPublicFixtures() throws {
  struct Fixture: Decodable {
    let id: String
    let audio: URL
    let sha256: String
    let expectedSpeech: Bool
  }
  struct Request: Decodable {
    let fixtures: [Fixture]
    let output: URL
  }
  struct Result: Encodable {
    let id: String
    let speech: Bool
  }
  let path = try #require(ProcessInfo.processInfo.environment["SILLIES_ACOUSTIC_REPLAY"])
  let manifest = URL(fileURLWithPath: path)
  let manifestSize = try manifest.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
  try #require((1...256 * 1_024).contains(manifestSize))
  let bytes = try Data(contentsOf: manifest)
  let request = try JSONDecoder().decode(Request.self, from: bytes)
  try #require((1...32).contains(request.fixtures.count) && request.output.isFileURL)
  try #require(!FileManager.default.fileExists(atPath: request.output.path))
  var results: [Result] = []
  for fixture in request.fixtures {
    try #require(fixture.audio.isFileURL)
    let audioSize = try fixture.audio.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    try #require((1...1_024 * 1_024).contains(audioSize))
    let audio = try Data(contentsOf: fixture.audio)
    try #require(
      SHA256.hash(data: audio).map { String(format: "%02x", $0) }.joined() == fixture.sha256)
    let file = try AVAudioFile(forReading: fixture.audio)
    try #require(
      file.processingFormat.sampleRate == 16_000 && file.processingFormat.channelCount == 1)
    try #require(file.length > 0 && file.length <= 192_000)
    let count = try #require(AVAudioFrameCount(exactly: file.length))
    let buffer = try #require(
      AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: count))
    try file.read(into: buffer)
    let samples = try #require(buffer.floatChannelData?[0])
    let detected = try WebRTCSpeechWindowValidator().containsSpeech(
      Array(UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength))))
    results.append(.init(id: fixture.id, speech: detected))
    #expect(detected == fixture.expectedSpeech, "Acoustic fixture: \(fixture.id)")
  }
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  try encoder.encode(results).write(to: request.output, options: .atomic)
}

@Test func speechRecognitionAcousticValidatorRejectsInvalidFramesAndSafelyPadsPartialFrames() throws
{
  let classifier = try WebRTCVoiceClassifier()
  for samples: [Float] in [[], [.nan], [.infinity], [Float](repeating: 0, count: 161)] {
    #expect(throws: SpeechError.self) { try classifier.isSpeech(samples) }
  }
  #expect(try !classifier.isSpeech([Float](repeating: 0, count: 17)))
}

@Test func speechRecognitionAcousticValidatorRejectsSilenceAndInvalidWindows() throws {
  let validator = WebRTCSpeechWindowValidator()
  #expect(try !validator.containsSpeech([]))
  #expect(try !validator.containsSpeech([Float](repeating: 0, count: 32_000)))
  #expect(throws: SpeechError.self) { try validator.containsSpeech([.nan]) }
  #expect(throws: SpeechError.self) {
    try validator.containsSpeech([Float](repeating: 0, count: 192_001))
  }
}

@Test func speechRecognitionAcousticValidatorHonorsTaskCancellation() async {
  let task = Task {
    withUnsafeCurrentTask { $0?.cancel() }
    return try WebRTCSpeechWindowValidator().containsSpeech([Float](repeating: 0, count: 192_000))
  }
  do {
    _ = try await task.value
    Issue.record("Cancelled acoustic analysis completed instead of stopping")
  } catch is CancellationError {
  } catch {
    Issue.record("Cancelled acoustic analysis returned an unrelated failure")
  }
}
