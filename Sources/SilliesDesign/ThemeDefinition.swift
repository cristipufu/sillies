import Foundation

package struct ThemeDefinition: Decodable, Equatable, Sendable, Identifiable {
  package let id: String
  package let name: String
  package let comment: String
  package let order: Int
  package let light: ThemePalette
  package let dark: ThemePalette
  private enum CodingKeys: String, CodingKey, CaseIterable {
    case version, id, name, comment, order, light, dark
  }
  private struct Field: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
  }
  package init(from decoder: any Decoder) throws {
    let fields = try decoder.container(keyedBy: Field.self).allKeys.map(\.stringValue)
    guard Set(fields) == Set(CodingKeys.allCases.map(\.rawValue)) else {
      throw ThemeCatalogFailure.invalid(String(localized: "Unknown or missing theme fields."))
    }
    let values = try decoder.container(keyedBy: CodingKeys.self)
    guard try values.decode(Int.self, forKey: .version) == 1 else {
      throw ThemeCatalogFailure.invalid(String(localized: "Unsupported theme version."))
    }
    id = try values.decode(String.self, forKey: .id)
    name = try values.decode(String.self, forKey: .name)
    comment = try values.decode(String.self, forKey: .comment)
    order = try values.decode(Int.self, forKey: .order)
    guard id.count <= 48,
      id.range(of: "^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$", options: .regularExpression)
        == (id.startIndex..<id.endIndex),
      !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 40,
      !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
      !comment.isEmpty, comment.count <= 240, (0...10_000).contains(order)
    else {
      throw ThemeCatalogFailure.invalid(String(localized: "Invalid theme identity or metadata."))
    }
    light = try values.decode(ThemePalette.self, forKey: .light)
    dark = try values.decode(ThemePalette.self, forKey: .dark)
  }
}

package enum ThemeCatalogFailure: LocalizedError {
  case invalid(String)
  package var errorDescription: String? {
    switch self {
    case .invalid(let reason): String(localized: "The theme could not be loaded: \(reason)")
    }
  }
}
