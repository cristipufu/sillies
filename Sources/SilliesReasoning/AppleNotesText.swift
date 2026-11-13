import Foundation
import SilliesTextModels

/// Normalizes the native model's focused text responses into the shared provider contracts.
enum AppleNotesText {
  static let listInstruction =
    "\nReturn only the requested entries, one per line. Return NONE if there are no entries."
  private static let bulletPrefixes = ["• ", "- ", "* "]

  static func items(_ response: String) -> [String] {
    let text = response.trimmingCharacters(in: .whitespacesAndNewlines)
    guard text != "NONE" else { return [] }
    return text.split(whereSeparator: \.isNewline).map { line in
      var item = String(line).trimmingCharacters(in: .whitespaces)
      if let prefix = bulletPrefixes.first(where: item.hasPrefix) { item.removeFirst(prefix.count) }
      if item.hasPrefix("\""), item.hasSuffix("\""), item.count > 1 {
        item.removeFirst()
        item.removeLast()
      }
      return item
    }.filter { !$0.isEmpty }
  }

  static func decision(_ response: String) throws -> GeneratedReasoningDecision {
    switch response.trimmingCharacters(
      in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "."))
    ).uppercased() {
    case "YES": .init(answer: true)
    case "NO": .init(answer: false)
    default: throw TextModelError.invalidResponse
    }
  }
}
