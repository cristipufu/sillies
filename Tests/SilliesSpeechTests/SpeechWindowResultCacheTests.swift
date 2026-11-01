import Testing

@testable import SilliesSpeech

@Test func finalWindowReuseRequiresIdenticalAudioPositionAndACompleteWindowEngine() {
  let draft = SpeechWindowBuffer.Window(samples: [1, 2, 3], start: 0, completion: .draft)
  let result = SpeechWindowResult(words: [.init(text: "hello", start: 0, end: 1)])
  var cache = SpeechWindowResultCache(policy: .reuseUnchangedDraft)
  cache.remember(result, for: draft)
  #expect(cache.result(for: draft) == nil)
  #expect(
    cache.result(for: .init(samples: draft.samples, start: 0, completion: .session))?.words
      == result.words)
  #expect(cache.result(for: .init(samples: [1, 2, 3, 4], start: 0, completion: .session)) == nil)
  #expect(cache.result(for: .init(samples: draft.samples, start: 1, completion: .session)) == nil)
  var streaming = SpeechWindowResultCache(policy: .decode)
  streaming.remember(result, for: draft)
  #expect(
    streaming.result(for: .init(samples: draft.samples, start: 0, completion: .session)) == nil)
}
