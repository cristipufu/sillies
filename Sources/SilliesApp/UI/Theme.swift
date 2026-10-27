import AppKit
import SwiftUI

enum SilliesTheme {
  static let accent = Color(red: 0.52, green: 0.47, blue: 0.77)
  static let paper = adaptive(light: "FAF8F4", dark: "24222A")
  static let card = adaptive(light: "FFFFFF", dark: "302D37")
  static let soft = adaptive(light: "F1EEE8", dark: "39353F")
  static let ink = adaptive(light: "37303F", dark: "F3EEF6")
  static let secondary = adaptive(light: "857E89", dark: "B0A6B8")
  static let border = adaptive(light: "E8E2DB", dark: "49424F")

  private static func adaptive(light: String, dark: String) -> Color {
    Color(
      nsColor: NSColor(name: nil) { appearance in
        NSColor(hex: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
      })
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
