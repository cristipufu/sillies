import AppKit
import SilliesDesign
import SwiftUI

struct SilliesTheme: Sendable, Equatable {
  enum Contrast: Sendable { case system, increased }
  let definition: ThemeDefinition?
  let contrast: Contrast
  init(definition: ThemeDefinition? = nil, contrast: Contrast = .system) {
    self.definition = definition
    self.contrast = contrast
  }
  var accent: Color { color(.accent) }
  var accentFill: Color { color(.accentFill) }
  var onAccent: Color { color(.onAccent) }
  var paper: Color { color(.paper) }
  var card: Color { color(.card) }
  var soft: Color { color(.soft) }
  var ink: Color { color(.ink) }
  var secondary: Color { color(.secondary) }
  var border: Color { color(.border) }
  var selection: Color { color(.selection) }
  var onSelection: Color { color(.onSelection) }
  var success: Color { color(.success) }
  var warning: Color { color(.warning) }
  var danger: Color { color(.danger) }
  private func color(_ role: ThemeColorRole) -> Color { Color(nsColor: native(role)) }

  func native(_ role: ThemeColorRole) -> NSColor {
    let theme = definition
    if contrast == .increased {
      return Self.accessibleColor(role)
    }
    return NSColor(name: nil) { appearance in
      let match = appearance.bestMatch(from: [
        .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
      ])
      if match == .accessibilityHighContrastAqua || match == .accessibilityHighContrastDarkAqua {
        return Self.accessibleColor(role)
      }
      let palette = match == .darkAqua ? theme?.dark : theme?.light
      guard let color = palette?[role] else {
        return DefaultThemeColors.color(role, appearance: appearance)
      }
      return NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1)
    }
  }
  nonisolated private static func accessibleColor(_ role: ThemeColorRole) -> NSColor {
    switch role {
    case .paper, .soft: .windowBackgroundColor
    case .card: .textBackgroundColor
    case .ink: .labelColor
    case .secondary: .secondaryLabelColor
    case .border: .separatorColor
    case .accent, .accentFill: .controlAccentColor
    case .onAccent: .selectedMenuItemTextColor
    case .selection: .selectedTextBackgroundColor
    case .onSelection: .selectedTextColor
    case .success: .systemGreen
    case .warning: .systemOrange
    case .danger: .systemRed
    }
  }
}

private struct SilliesThemeKey: EnvironmentKey {
  static let defaultValue = SilliesTheme()
}

extension EnvironmentValues {
  var silliesTheme: SilliesTheme {
    get { self[SilliesThemeKey.self] }
    set { self[SilliesThemeKey.self] = newValue }
  }
}
