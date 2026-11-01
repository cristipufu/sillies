import Foundation
import SilliesCore
import SilliesTextModels

/// Published text cannot be taken back. Recovery may restart inference only before the first delta.
actor ConversationStreamDelivery {
  private let receive: ConversationTextSink
  private var text = ""
  var hasOutput: Bool { !text.isEmpty }
  init(receive: @escaping ConversationTextSink) { self.receive = receive }
  func finalized(matching result: String) throws -> String {
    guard
      text.trimmingCharacters(in: .whitespacesAndNewlines)
        == result.trimmingCharacters(in: .whitespacesAndNewlines)
    else {
      throw TextModelError.invalidResponse
    }
    return text
  }
  func append(_ delta: String) async throws {
    try Task.checkCancellation()
    guard !delta.isEmpty else { return }
    guard delta.utf8.count <= ChatContext.maximumMessageBytes - text.utf8.count,
      text.count + delta.count <= ChatContext.maximumMessageCharacters
    else {
      throw TextModelError.invalidResponse
    }
    text += delta
    try await receive(delta)
  }
}
