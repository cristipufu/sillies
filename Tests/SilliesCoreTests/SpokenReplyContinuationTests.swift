import SilliesCore
import Testing

@Test func speechContinuationUsesOnlyTheMatchingUnspokenSuffix() throws {
  let reply = ChatMessage(role: .companion, text: "Heat water.\n\nAdd tea. Finally, steep.")
  let continuation = try #require(
    SpokenReplyContinuation(reply.withDelivery(.interrupted, spokenText: "Heat water.")))
  #expect(continuation.messageID == reply.id)
  #expect(continuation.completedText == "Heat water.")
  #expect(continuation.remainingText == "Add tea. Finally, steep.")
  #expect(
    SpokenReplyContinuation(reply.withDelivery(.complete, spokenText: ""))?.remainingText
      == "Heat water. Add tea. Finally, steep.")
  #expect(SpokenReplyContinuation(reply.withDelivery(.complete, spokenText: reply.text)) == nil)
}

@Test func speechContinuationRejectsUnknownOrInconsistentPlaybackAndOversizedMessages() {
  let reply = ChatMessage(role: .companion, text: "Heat water. Add tea.")
  for spoken in ["He", "Different words", "Heat water. Add tea. More."] {
    #expect(SpokenReplyContinuation(reply.withDelivery(.complete, spokenText: spoken)) == nil)
  }
  #expect(SpokenReplyContinuation(reply) == nil)
  #expect(SpokenReplyContinuation(reply.withDelivery(.streaming, spokenText: "")) == nil)
  #expect(
    SpokenReplyContinuation(
      ChatMessage(role: .user, text: "Hello").withDelivery(.complete, spokenText: "")) == nil)
  let oversized = reply.withText(
    String(repeating: "a", count: ChatContext.maximumMessageCharacters + 1))
  #expect(SpokenReplyContinuation(oversized.withDelivery(.complete, spokenText: "")) == nil)
}
