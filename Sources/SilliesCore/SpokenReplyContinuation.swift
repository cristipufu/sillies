import Foundation

/// Resume written words after a verified playback prefix. Never guess past mismatched evidence.
public struct SpokenReplyContinuation: Sendable {
  public let messageID: UUID
  public let completedText: String
  public let remainingText: String

  public init?(_ message: ChatMessage) {
    guard message.role == .companion, message.completion != .streaming,
      let spokenText = message.spokenText,
      message.text.count <= ChatContext.maximumMessageCharacters,
      message.text.utf8.count <= ChatContext.maximumMessageBytes
    else { return nil }
    let text = Self.normalized(message.text)
    let completed = Self.normalized(spokenText)
    guard text.hasPrefix(completed) else { return nil }
    let remainder = text.dropFirst(completed.count)
    guard !remainder.isEmpty,
      completed.isEmpty || remainder.first?.isWhitespace == true
    else { return nil }
    messageID = message.id
    completedText = completed
    remainingText = String(remainder).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !remainingText.isEmpty else { return nil }
  }

  private static func normalized(_ text: String) -> String {
    text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }
}
