import Foundation
import SilliesDesign
import Testing

@Test func allBundledThemesHaveReadableCompletePalettes() async throws {
  let themes = try await Task.detached { try ThemeCatalog.loadBundled() }.value
  #expect(
    Set(themes.map(\.id)).isSuperset(of: ["sillies", "catppuccin", "tokyo-night", "dracula"]))
  for theme in themes {
    for palette in [theme.light, theme.dark] {
      for role in ThemeColorRole.allCases { #expect(palette[role] != nil) }
    }
  }
}

@Test func themeColorsRejectMalformedValuesInsteadOfCrashing() throws {
  for invalid in ["red", "#123", "#0000000", "#+00001", "#GGGGGG", "#123456\n"] {
    #expect(throws: (any Error).self) { try ThemeColor(hex: invalid) }
  }
  let black = try ThemeColor(hex: "#000000")
  let white = try ThemeColor(hex: "#FFFFFF")
  #expect(abs(black.contrast(with: white) - 21) < 0.001)
}

@Test func themeSchemaRejectsUnreadableMissingAndUnknownRoles() async throws {
  let themes = try await Task.detached { try ThemeCatalog.loadBundled() }.value
  let palette = try #require(themes.first?.light)
  let encoded = try JSONEncoder().encode(palette)
  var colors = try JSONDecoder().decode([String: String].self, from: encoded)
  colors["ink"] = colors["paper"]
  #expect(throws: (any Error).self) {
    try JSONDecoder().decode(ThemePalette.self, from: JSONEncoder().encode(colors))
  }
  colors.removeValue(forKey: "ink")
  #expect(throws: (any Error).self) {
    try JSONDecoder().decode(ThemePalette.self, from: JSONEncoder().encode(colors))
  }
  colors["ink"] = "#000000"
  colors["typo"] = "#123456"
  #expect(throws: (any Error).self) {
    try JSONDecoder().decode(ThemePalette.self, from: JSONEncoder().encode(colors))
  }
}
