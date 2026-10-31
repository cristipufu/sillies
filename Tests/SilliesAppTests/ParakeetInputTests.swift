import AVFoundation
import SilliesModelStore
import SilliesSpeech
import Synchronization
import Testing

@testable import SilliesApp
@testable import SilliesSpeechParakeet

@Test(arguments: [1, 160, 4_799, 4_800, 16_000])
func parakeetPreservesShortSpeechAndPadsOnlyDecoderContext(_ count: Int) throws {
  let original = [Float](repeating: 0.1, count: count)
  let input = try ParakeetTranscriptionInput(.init(samples: original, language: .automatic))
  #expect(input.samples.count == max(count, 4_800))
  #expect(Array(input.samples.prefix(count)) == original)
  #expect(input.samples.dropFirst(count).allSatisfy { $0 == 0 })
  #expect(input.language == nil)
}

@Test(arguments: ["ro", "ro_RO", "en", "en-US"])
func parakeetForwardsLanguageHints(_ identifier: String) throws {
  let language = SpeechLanguage(id: identifier, name: identifier, isInstalled: true)
  let input = try ParakeetTranscriptionInput(.init(samples: [0.1], language: language))
  #expect(input.language?.rawValue == language.locale.language.languageCode?.identifier)
}

@Test func parakeetCatalogOffersRealHintsForEveryAdvertisedLanguage() async throws {
  let model = try SpeechModelCatalog.bundled().manifest(for: "parakeet-ultra").model
  #expect(model.capabilities.languageControl == .hinted)
  for id in model.capabilities.languages {
    let input = try ParakeetTranscriptionInput(
      .init(
        samples: [0.1], language: .init(id: id, name: id, isInstalled: true)))
    #expect(input.language?.rawValue == id)
  }
}

@Test func shortParakeetFinalWindowCompletesWithoutLosingSpeechOrExtendingTime() async throws {
  let output = Mutex<[SpeechPhrase]>([])
  let failures = Mutex<[String]>([])
  let model = WindowSpeechModel(engine: ParakeetBoundaryFixture())
  let channel = try await model.makeChannel(
    .init(
      language: .automatic, output: { phrase in output.withLock { $0.append(phrase) } },
      failure: { failure in failures.withLock { $0.append(failure) } }))
  let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
  let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600))
  buffer.frameLength = buffer.frameCapacity
  for index in 0..<Int(buffer.frameLength) { buffer.floatChannelData?[0][index] = 0.1 }
  channel.append(buffer)
  await withCheckedContinuation { continuation in channel.finish { continuation.resume() } }
  #expect(failures.withLock { $0 }.isEmpty)
  let phrases = output.withLock { $0 }
  #expect(phrases.last?.text == "Da.")
  #expect(phrases.last?.duration == 0.1)
}

private actor ParakeetBoundaryFixture: SpeechWindowEngine {
  func transcribe(_ request: SpeechWindowRequest) async throws -> SpeechWindowResult {
    let input = try ParakeetTranscriptionInput(request)
    guard input.samples.count >= 4_800 else { throw SpeechError.unavailable("Under 300ms") }
    return .init(words: [.init(text: "Da.", start: 0, end: 0.1)])
  }
}
