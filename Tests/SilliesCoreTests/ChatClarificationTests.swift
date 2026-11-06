import Foundation
import Testing

@testable import SilliesCore

@Test func clarificationPersistenceRejectsMalformedQuestionsAndResolutionsStayFinal() throws {
  let question = try #require(
    ChatClarification(question: "Which meeting?", choices: ["Planning", "Review"]))
  let encoded = try JSONEncoder().encode(question)
  var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
  object["choices"] = ["Same", "Same"]
  #expect(throws: DecodingError.self) {
    try JSONDecoder().decode(
      ChatClarification.self, from: JSONSerialization.data(withJSONObject: object))
  }
  object["choices"] = ["Planning", "Review"]
  object["question"] = String(
    repeating: "x", count: ChatClarification.maximumQuestionCharacters + 1)
  #expect(throws: DecodingError.self) {
    try JSONDecoder().decode(
      ChatClarification.self, from: JSONSerialization.data(withJSONObject: object))
  }
  for resolution in [ChatClarification.Resolution.answered, .cancelled, .superseded] {
    let resolved = question.resolving(resolution)
    #expect(resolved.resolving(.pending) == resolved)
    #expect(
      try JSONDecoder().decode(ChatClarification.self, from: JSONEncoder().encode(resolved))
        == resolved)
  }
}
