import Foundation

public struct ConversationMarkdownFormatter {
  private let companionName: String
  private let dates = ISO8601DateFormatter()
  public init(companionName: String) {
    self.companionName = companionName.components(separatedBy: .newlines).joined(separator: " ")
  }
  public var heading: String { "# \(String(localized: "Conversation with \(companionName)"))\n\n" }
  public func message(_ entry: ConversationEntry) -> String {
    let speaker = entry.message.role == .user ? String(localized: "You") : companionName
    var text = "## \(speaker) · \(dates.string(from: entry.createdAt))\n\n\(entry.message.text)\n\n"
    if entry.message.completion == .interrupted { text += "*\(String(localized: "Stopped"))*\n\n" }
    return text
  }
}
