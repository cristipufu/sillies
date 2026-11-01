import Foundation

enum ThemeFixtures {
  static func verify() -> Bool {
    let fixtures: [(String, Bool)] = [
      ("Text(value).foregroundStyle(theme.ink)", true),
      ("static var preferences: AppearancePreferences?", false),
      ("static let shared = ThemeEnvironment()", false),
      ("init(appearance: ThemeEnvironment = .init()) {}", false),
      ("init(appearance: ThemeEnvironment? = nil) {}", false),
      ("init(appearance: ThemeEnvironment) {}", true),
      ("let appearance: ThemeEnvironment = .init()", false),
      ("let appearance = ThemeEnvironment()", false),
      ("let appearance = ThemeEnvironment.init()", false),
      ("let appearance = SilliesApp.ThemeEnvironment()", false),
      ("let appearance: ThemeEnvironment = services.appearance", true),
      ("static var palette = SilliesTheme()", false),
      ("static let defaultValue = SilliesTheme()", true),
      ("SilliesTheme.configure(preferences)", false),
      ("AppWindowAppearance.shared.register(window)", false),
      ("NSHostingView(rootView: content)", false),
      ("ThemedHostingView(rootView: content, appearance: appearance)", true),
      ("let palette = SilliesTheme()", true),
      ("Text(value).foregroundStyle(.white)", false),
      ("Circle().fill(Color.red)", false),
      (#"Color(hex: "FFFFFF")"#, false),
      ("Color(red: 1, green: 0, blue: 0)", false),
      ("Color(hex: character.accent)", true),
      ("Color(.sRGB, red: palette.red, green: palette.green, blue: palette.blue)", true),
      ("view.shadow(color: .black.opacity(0.15), radius: 3)", true),
    ]
    for (source, valid) in fixtures {
      guard
        ThemeVisitor.check(source: source, path: "Sources/SilliesApp/UI/NewView.swift").isEmpty
          == valid
      else {
        fputs("Theme fixture failed: \(source)\n", stderr)
        return false
      }
    }
    guard
      ThemeVisitor.check(
        source: "private let appearance = ThemeEnvironment()",
        path: "Sources/SilliesApp/App/SilliesMain.swift"
      ).isEmpty
    else {
      fputs("Theme composition fixture failed\n", stderr)
      return false
    }
    print("Theme colors: \(fixtures.count) syntax fixtures passed.")
    return true
  }
}
