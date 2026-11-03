import Foundation
import Testing

@testable import SilliesTextModels

@Test func conversationContinuationRequiresExactSessionHistoryAndInstructions() {
  let id = UUID()
  let user = TextMessage(role: .user, content: "Remember 14:30.")
  let reply = TextGenerationOutput(text: "I will.")
  let first = request([user], session: id)
  let cached = TextConversationContinuation(request: first, response: reply)
  let history = [user, TextMessage(role: .assistant, content: reply.text)]
  let next = TextMessage(role: .user, content: "When?")
  #expect(cached.suffix(for: request(history + [next], session: id)) == [next])
  #expect(cached.suffix(for: request(history + [next], session: UUID())) == nil)
  #expect(cached.suffix(for: request(history + [next], session: nil)) == nil)
  #expect(cached.suffix(for: request([next], session: id)) == nil)
  #expect(cached.suffix(for: request(history, session: id)) == nil)
  #expect(
    cached.suffix(for: request(history + [next], session: id, instructions: "New memory")) == nil)
  let revised = [user, TextMessage(role: .assistant, content: "Interrupted reply"), next]
  #expect(cached.suffix(for: request(revised, session: id)) == nil)
}

@Test func conversationContinuationPreservesToolIdentityAndRejectsChangedSchemas() {
  let id = UUID()
  let first = request([.init(role: .user, content: "Find my notes")], session: id)
  let call = TextGenerationOutput.Call(id: "one", name: "search", arguments: Data("{}".utf8))
  let result = TextMessage.result("Saved notes", for: call)
  let cached = TextConversationContinuation(
    request: first, response: .init(text: "", calls: [call]))
  let messages = first.messages + [.calling([call], text: ""), result]
  #expect(cached.suffix(for: request(messages, session: id)) == [result])
  let changed = TextGenerationRequest(
    conversation: .init(
      instructions: first.instructions, messages: messages,
      tools: [.init(name: "another", description: "Different tool", parameters: [])]),
    maximumTokens: 100, style: .precise
  ).inSession(id)
  #expect(cached.suffix(for: changed) == nil)
}

@Test func conversationContinuationRequiresTheExactPrivateStateOfAnActiveToolTurn() {
  let id = UUID()
  let call = TextGenerationOutput.Call(id: "one", name: "search", arguments: Data("{}".utf8))
  let first = request([.init(role: .user, content: "Find my notes")], session: id)
  let response = TextGenerationOutput(text: "", calls: [call], reasoningContent: "Private state")
  let cached = TextConversationContinuation(request: first, response: response)
  let result = TextMessage.result("Saved notes", for: call)
  let exact =
    first.messages + [.calling([call], text: "", reasoningContent: "Private state"), result]
  #expect(cached.suffix(for: request(exact, session: id)) == [result])
  let missing = first.messages + [.calling([call], text: ""), result]
  #expect(cached.suffix(for: request(missing, session: id)) == nil)
}

private func request(_ messages: [TextMessage], session: UUID?, instructions: String = "Be helpful")
  -> TextGenerationRequest
{
  TextGenerationRequest(
    conversation: .init(instructions: instructions, messages: messages, tools: []),
    maximumTokens: 100, style: .precise
  ).inSession(session)
}
