import Foundation
import SilliesCore
import Testing

@Test func replyInspectionSurvivesPersistenceWithoutEnteringMessageText() throws {
  let input = ChatContext(
    companionName: "Pogo", profile: .init(personality: "Curious"),
    messages: [.init(role: .user, text: "A private question")],
    memory: .init(summary: "Fallible notes"))
  let inspection = ReplyContextInspection(
    context: input, availableTools: 4, workingContextTokens: 4096)
  let message = ChatMessage(role: .companion, text: "An answer").inspecting(inspection)
  let restored = try JSONDecoder().decode(ChatMessage.self, from: JSONEncoder().encode(message))
  #expect(restored.contextInspection == inspection)
  #expect(restored.text == "An answer")
  #expect(restored.contextInspection?.recentMessages == 1)
  var withoutInspection = try #require(
    JSONSerialization.jsonObject(with: JSONEncoder().encode(message)) as? [String: Any])
  withoutInspection.removeValue(forKey: "contextInspection")
  let older = try JSONDecoder().decode(
    ChatMessage.self, from: JSONSerialization.data(withJSONObject: withoutInspection))
  #expect(older.contextInspection == nil)
  #expect(older.text == message.text)
}
