import Foundation
import SilliesCore
import SilliesTTS

/// Synthetic inputs only. Expectations and listening scores remain outside model requests.
struct VoiceConversationScenario: Codable {
  let id: String
  let language: String
  let prompt: String

  static let rainbow = Self(
    id: "rainbow", language: "en",
    prompt: "In three short sentences, explain why rainbows have different colours.")

  static func load(_ path: String) throws -> Self {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    guard data.count <= ChatContext.maximumMessageBytes else { throw TTSError.invalidRequest }
    let scenario = try JSONDecoder().decode(Self.self, from: data)
    guard !scenario.id.isEmpty, scenario.id.count <= 80,
      !scenario.language.isEmpty, scenario.language.count <= 64,
      !scenario.prompt.isEmpty, scenario.prompt.count <= ChatContext.maximumMessageCharacters
    else { throw TTSError.invalidRequest }
    return scenario
  }
}
