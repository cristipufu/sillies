import Foundation

/// Recover only planned phrases after the last confirmed playback boundary, never inferred words.
public struct SpokenReplyProgress: Sendable {
  private var phrases: [String] = []
  private var completedCount = 0
  private var characterCount = 0
  private var byteCount = 0
  private var isConsistent = true

  public init() {}

  public var completedText: String {
    phrases.prefix(completedCount).joined(separator: " ")
  }
  public var remainingPhrases: [String] {
    isConsistent ? Array(phrases.dropFirst(completedCount)) : []
  }

  public mutating func append(_ phrase: String) {
    guard isConsistent, !phrase.isEmpty else { return }
    let separatorCount = phrases.isEmpty ? 0 : 1
    guard phrase.count + separatorCount <= ChatContext.maximumMessageCharacters - characterCount,
      phrase.utf8.count + separatorCount <= ChatContext.maximumMessageBytes - byteCount
    else {
      isConsistent = false
      return
    }
    phrases.append(phrase)
    characterCount += phrase.count + separatorCount
    byteCount += phrase.utf8.count + separatorCount
  }

  public mutating func completed(_ phrase: String) {
    guard isConsistent, completedCount < phrases.count, phrases[completedCount] == phrase else {
      isConsistent = false
      return
    }
    completedCount += 1
  }
}
