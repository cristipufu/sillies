import Foundation
import SilliesCore

/// Complete JSON representations keep provenance and coverage even under a smaller tool budget.
struct ConversationSearchEvidence: Encodable {
  enum Status: String, Encodable { case matches, noMatches, queryRequired }
  struct Message: Encodable {
    // Indexed words can be arbitrarily long. Measure escaped JSON, not characters or FTS tokens.
    private static let maximumExcerptBytes = 1_600
    let messageID: UUID
    let sequence: Int64
    let date: Date
    let speaker: String
    let excerpt: String
    let isCompleteMessage: Bool
    let omissionReason: String?

    init(_ match: ConversationSearchMatch) throws {
      messageID = match.id
      sequence = match.entry.sequence
      date = match.entry.createdAt
      speaker = match.entry.message.role == .user ? "user" : "companion"
      if try JSONEncoder().encode(match.excerpt).count > Self.maximumExcerptBytes {
        excerpt = ""
        isCompleteMessage = false
        omissionReason =
          "The matching excerpt exceeds the size allowance; no source text is included."
      } else {
        excerpt = match.excerpt
        isCompleteMessage = match.excerpt == match.entry.message.text
        omissionReason = nil
      }
    }
  }

  let source = "conversation"
  let query: String
  let status: Status
  let hasMoreMatches: Bool
  let messages: [Message]

  init(query: String, matches: [ConversationSearchMatch], limit: Int) throws {
    self.query = query
    status = query.isEmpty ? .queryRequired : matches.isEmpty ? .noMatches : .matches
    hasMoreMatches = matches.count > limit
    // Choose by relevance, present in conversation order so corrections have an explicit chronology.
    messages = try matches.prefix(limit).sorted { $0.entry.sequence < $1.entry.sequence }.map(
      Message.init)
  }

  func encoded() throws -> String {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return String(decoding: try encoder.encode(self), as: UTF8.self)
  }
}
