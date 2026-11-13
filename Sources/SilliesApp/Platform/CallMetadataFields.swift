import Foundation

/// Reads comma-delimited metadata without splitting a person's parenthesized display name.
struct CallMetadataFields {
  let values: [String]
  init?(_ label: String) {
    guard label.utf8.count <= CallSpeakerText.maximumMetadataBytes else { return nil }
    var fields: [String] = []
    var field = ""
    var parentheses = 0
    for character in label.precomposedStringWithCompatibilityMapping {
      switch character {
      case "(": parentheses += 1
      case ")":
        guard parentheses > 0 else { return nil }
        parentheses -= 1
      case let separator where (separator == "," || separator == "、") && parentheses == 0:
        guard Self.finish(&field, into: &fields) else { return nil }
        continue
      default: break
      }
      field.append(character)
    }
    guard parentheses == 0, Self.finish(&field, into: &fields) else { return nil }
    values = fields
  }
  private static func finish(_ field: inout String, into fields: inout [String]) -> Bool {
    let value = field.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return false }
    fields.append(value)
    field.removeAll(keepingCapacity: true)
    return true
  }
  static func words(_ value: String) -> [String] {
    CallSpeakerText.normalize(value).split(whereSeparator: \.isWhitespace).map(String.init)
  }
}
