import Foundation

package enum ThemeColorRole: String, CaseIterable, Codable, Sendable {
  case paper, card, soft, ink, secondary, border, accent, accentFill, onAccent
  case selection, onSelection, success, warning, danger
}

/// Semantic roles keep application chrome independent of palette names and artwork colors.
package struct ThemePalette: Codable, Equatable, Sendable {
  private let colors: [ThemeColorRole: ThemeColor]
  package init(colors: [ThemeColorRole: ThemeColor]) throws {
    guard Set(colors.keys) == Set(ThemeColorRole.allCases) else {
      throw ThemeCatalogFailure.invalid(
        String(localized: "A palette must define every semantic color role."))
    }
    self.colors = colors
    try validateContrast()
  }
  package init(from decoder: any Decoder) throws {
    let values = try decoder.singleValueContainer().decode([String: ThemeColor].self)
    var colors: [ThemeColorRole: ThemeColor] = [:]
    for (key, value) in values {
      guard let role = ThemeColorRole(rawValue: key) else {
        throw ThemeCatalogFailure.invalid(String(localized: "Unknown color role: \(key)."))
      }
      colors[role] = value
    }
    try self.init(colors: colors)
  }
  package func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(
      Dictionary(uniqueKeysWithValues: colors.map { ($0.key.rawValue, $0.value) }))
  }
  package subscript(_ role: ThemeColorRole) -> ThemeColor? { colors[role] }

  private func validateContrast() throws {
    let textRoles: [ThemeColorRole] = [.ink, .secondary, .accent, .success, .warning, .danger]
    let surfaces: [ThemeColorRole] = [.paper, .card, .soft]
    for foreground in textRoles {
      for background in surfaces { try requireContrast(foreground, on: background) }
    }
    try requireContrast(.onAccent, on: .accentFill)
    try requireContrast(.onSelection, on: .selection)
  }
  private func requireContrast(_ foreground: ThemeColorRole, on background: ThemeColorRole) throws {
    guard let foregroundColor = colors[foreground], let backgroundColor = colors[background],
      foregroundColor.contrast(with: backgroundColor) >= 4.5
    else {
      throw ThemeCatalogFailure.invalid(
        String(
          localized: "\(foreground.rawValue) needs 4.5:1 contrast against \(background.rawValue)."))
    }
  }
}
