import Foundation
import SilliesTextModels

/// Display-language changes never rename the source-language identities used for evidence and updates.
struct MeetingTopicTitleTranslator {
  let inference: NotesInference
  func titles(in catalog: MeetingTopicCatalog, localeIdentifier: String?) async throws -> [String] {
    let titles = try await LocalNotesTranslation.translate(
      catalog.topics.map(\.title), localeIdentifier: localeIdentifier, inference: inference)
    guard
      titles.allSatisfy({
        !$0.contains(where: \.isNewline) && $0.count <= MeetingTopicDiscovery.maximumTitleCharacters
      })
    else {
      throw TextModelError.invalidResponse
    }
    return titles
  }
}
