import Foundation

enum ThemeFixtures {
  static func verify() -> Bool {
    let fixtures: [(String, Bool)] = [
      ("Text(value).foregroundStyle(SilliesTheme.ink)", true),
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
    print("Theme colors: \(fixtures.count) syntax fixtures passed.")
    return true
  }
}
