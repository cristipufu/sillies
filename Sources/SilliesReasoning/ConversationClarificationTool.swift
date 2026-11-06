import Foundation
import SilliesCore

/// Offers real alternatives when guessing would change the answer. It never waits for the UI.
package struct ConversationClarificationTool: ConversationTool {
  package static let name = "request_clarification"
  package init() {}
  package let definition = ConversationToolDefinition(
    name: Self.name,
    description: """
      Resolve ambiguity about what the user wants, such as which of several saved meetings they mean.
      Ask the user to choose between two or three interpretations in their language, using real evidence.
      This cannot answer factual questions: answer those directly. Do not turn questions into quizzes.
      The app displays the question and ends this turn until the user answers.
      """,
    parameters: [
      .init("question", description: "A concise question, at most 400 characters."),
      .init("first_choice", description: "First concrete alternative, at most 120 characters."),
      .init("second_choice", description: "Second distinct alternative, at most 120 characters."),
      .init(
        "third_choice", description: "Optional third alternative, at most 120 characters.",
        requirement: .optional),
    ])
  package var activity: String { String(localized: "Preparing a question…") }

  package func call(arguments: Data) throws -> ConversationToolOutput {
    let input = try ConversationToolArguments.decode(Arguments.self, from: arguments)
    let question = try ConversationToolArguments.require(
      ChatClarification(
        question: input.question,
        choices: [input.firstChoice, input.secondChoice] + (input.thirdChoice.map { [$0] } ?? [])
      ))
    let result = Result(question: question.question, choices: question.choices)
    return .init(text: String(decoding: try JSONEncoder().encode(result), as: UTF8.self)).asking(
      question)
  }

  private struct Arguments: Decodable {
    let question: String
    let firstChoice: String
    let secondChoice: String
    let thirdChoice: String?
    private enum CodingKeys: String, CodingKey {
      case question
      case firstChoice = "first_choice"
      case secondChoice = "second_choice"
      case thirdChoice = "third_choice"
    }
  }
  private struct Result: Encodable {
    let status = "awaiting_user_answer"
    let question: String
    let choices: [String]
    let instruction =
      "The app presents this question, choices and a free-text answer. This turn is complete. Wait for the next user message."
  }
}
