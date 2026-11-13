import Foundation
import SilliesTextModels

/// Updates one subject at a time. Every source slice survives admission without prefix truncation.
struct MeetingTopicWriter {
  static let maximumBodyCharacters = 1_600
  let inference: NotesInference

  func update(_ input: MeetingNotesPrompt.Update) async throws -> String {
    try Task.checkCancellation()
    guard !input.source.isEmpty else { return input.previous }
    let request = MeetingNotesPrompt.update(input)
    guard try await inference.admits(request, format: .meetingTopicBody) else {
      return try await updateHalves(input)
    }
    let response = try await inference.response(
      GeneratedMeetingTopicBody.self,
      request: request, format: .meetingTopicBody)
    let body = response.body.trimmingCharacters(in: .whitespacesAndNewlines)
    guard body.count <= Self.maximumBodyCharacters,
      Self.numbers(in: body).isSubset(
        of: Self.numbers(in: input.previous + "\n" + input.source.text))
    else { throw TextModelError.invalidResponse }
    return body.isEmpty ? input.previous : body
  }

  private func updateHalves(_ input: MeetingNotesPrompt.Update) async throws -> String {
    guard let halves = input.source.halves() else { throw TextModelError.contextLimit }
    let first = try await update(input.replacingSource(halves.first, previous: input.previous))
    return try await update(input.replacingSource(halves.last, previous: first))
  }

  private static func numbers(in text: String) -> Set<String> {
    Set(text.split { !$0.isNumber }.map(String.init))
  }
}
