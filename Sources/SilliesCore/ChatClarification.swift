import Foundation

/// A completed turn can ask one bounded question. Waiting for its answer owns no inference work.
public struct ChatClarification: Codable, Equatable, Identifiable, Sendable {
  public enum Resolution: String, Codable, Sendable {
    case pending, answered, cancelled, superseded
  }
  public static let maximumQuestionCharacters = 400
  public static let maximumChoiceCharacters = 120
  public static let maximumChoices = 3
  public let id: UUID
  public let question: String
  public let choices: [String]
  public private(set) var resolution: Resolution = .pending

  public init?(question: String, choices: [String]) {
    self.init(id: UUID(), question: question, choices: choices, resolution: .pending)
  }

  private init?(id: UUID, question: String, choices: [String], resolution: Resolution) {
    let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
    let choices = choices.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    guard !question.isEmpty, question.count <= Self.maximumQuestionCharacters,
      (2...Self.maximumChoices).contains(choices.count), Set(choices).count == choices.count,
      choices.allSatisfy({ !$0.isEmpty && $0.count <= Self.maximumChoiceCharacters })
    else { return nil }
    self.id = id
    self.question = question
    self.choices = choices
    self.resolution = resolution
  }

  private enum CodingKeys: String, CodingKey { case id, question, choices, resolution }
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    guard
      let validated = try Self(
        id: values.decode(UUID.self, forKey: .id),
        question: values.decode(String.self, forKey: .question),
        choices: values.decode([String].self, forKey: .choices),
        resolution: values.decode(Resolution.self, forKey: .resolution))
    else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "Invalid clarification bounds"))
    }
    self = validated
  }

  public func resolving(_ resolution: Resolution) -> Self {
    var copy = self
    if copy.resolution == .pending { copy.resolution = resolution }
    return copy
  }
}
