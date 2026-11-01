/// A complete-window recognizer can finalize its last draft without decoding identical audio again.
/// Incremental recognizers must still flush their decoder at completion.
struct SpeechWindowResultCache {
  private struct Entry {
    let start: Double
    let sampleCount: Int
    let result: SpeechWindowResult
  }
  private let policy: SpeechFinalizationPolicy
  private var entry: Entry?

  init(policy: SpeechFinalizationPolicy) { self.policy = policy }

  func result(for window: SpeechWindowBuffer.Window) -> SpeechWindowResult? {
    guard policy == .reuseUnchangedDraft, window.completion != .draft,
      let entry, entry.start == window.start, entry.sampleCount == window.samples.count
    else { return nil }
    return entry.result
  }

  mutating func remember(_ result: SpeechWindowResult, for window: SpeechWindowBuffer.Window) {
    guard policy == .reuseUnchangedDraft else { return }
    entry = Entry(start: window.start, sampleCount: window.samples.count, result: result)
  }
}
