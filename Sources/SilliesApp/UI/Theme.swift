import AppKit
import SilliesDesign
import SwiftUI

@MainActor
enum SilliesTheme {
  enum Contrast { case system, increased }
  private static var preferences: AppearancePreferences?
  static func configure(_ preferences: AppearancePreferences) { self.preferences = preferences }
  static var revision: Int { preferences?.revision ?? 0 }
  static var accent: Color { color(.accent) }
  static var accentFill: Color { color(.accentFill) }
  static var onAccent: Color { color(.onAccent) }
  static var paper: Color { color(.paper) }
  static var card: Color { color(.card) }
  static var soft: Color { color(.soft) }
  static var ink: Color { color(.ink) }
  static var secondary: Color { color(.secondary) }
  static var border: Color { color(.border) }
  static var selection: Color { color(.selection) }
  static var onSelection: Color { color(.onSelection) }
  static var success: Color { color(.success) }
  static var warning: Color { color(.warning) }
  static var danger: Color { color(.danger) }
  private static func color(_ role: ThemeColorRole) -> Color { Color(nsColor: native(role)) }

  static func native(_ role: ThemeColorRole, contrast: Contrast = .system) -> NSColor {
    // Access during view rendering participates in Observation. The color callback captures values only.
    _ = revision
    let theme = preferences?.selectedTheme
    if contrast == .increased || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
      return accessibleColor(role)
    }
    return NSColor(name: nil) { appearance in
      let match = appearance.bestMatch(from: [
        .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
      ])
      if match == .accessibilityHighContrastAqua || match == .accessibilityHighContrastDarkAqua {
        return accessibleColor(role)
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

struct CharacterPortrait: NSViewRepresentable {
  let renderer: String
  let size: Double
  let registry: RendererRegistry

  func makeNSView(context: Context) -> CompanionView {
    let rig = registry.make(renderer) ?? CharacterRig()
    return CompanionView.makePortrait(rig: rig, size: size)
  }

  func updateNSView(_ view: CompanionView, context: Context) { view.resize(to: size) }
}

struct SoftButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .padding(.horizontal, 12).padding(.vertical, 8)
      .background(
        SilliesTheme.accent.opacity(configuration.isPressed ? 0.20 : 0.10),
        in: RoundedRectangle(cornerRadius: 9)
      )
      .foregroundStyle(SilliesTheme.accent)
  }
}
