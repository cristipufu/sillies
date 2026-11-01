import Foundation
import SilliesDesign
import Testing

@Test func themeContributionsAreDiscoveredAndInvalidFilesFailRecoverably() async throws {
  try await Task.detached {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { removeDesignFixture(directory) }
    let original = try #require(ThemeCatalog.loadBundled().first)
    let palette = try JSONDecoder().decode(
      [String: String].self, from: JSONEncoder().encode(original.light))
    let data = try JSONSerialization.data(withJSONObject: [
      "version": 1, "id": "new-theme", "name": "New Theme", "comment": "Contributor fixture",
      "order": 10, "light": palette, "dark": palette,
    ])
    let file = directory.appendingPathComponent("new-theme.json")
    try data.write(to: file)
    #expect(try ThemeCatalog.load(from: directory).map(\.id) == ["new-theme"])
    let invalid = directory.appendingPathComponent("wrong-name.json")
    try data.write(to: invalid)
    #expect(throws: (any Error).self) { try ThemeCatalog.load(from: directory) }
    try FileManager.default.removeItem(at: invalid)
    try Data(repeating: 32, count: 20_000).write(to: file)
    #expect(throws: (any Error).self) { try ThemeCatalog.load(from: directory) }
    try FileManager.default.removeItem(at: file)
    try FileManager.default.createSymbolicLink(at: file, withDestinationURL: directory)
    #expect(throws: (any Error).self) { try ThemeCatalog.load(from: directory) }
  }.value
}

@Test func languageMetadataRejectsDuplicateUnsafeAndOversizedContributions() async throws {
  try await Task.detached {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { removeDesignFixture(file) }
    let english = ["code": "en", "language": "English", "english": "English"]
    let welsh = ["code": "cy", "language": "Cymraeg", "english": "Welsh"]
    try JSONSerialization.data(withJSONObject: [english, welsh]).write(to: file)
    #expect(try Set(LanguageCatalog.load(from: file).map(\.id)) == ["en", "cy"])
    for invalid in [
      [english, english],
      [english, ["code": "../de", "language": "Deutsch", "english": "German"]],
      [english, ["code": "fr", "language": "", "english": "French"]],
      [english, ["code": "fr\n", "language": "Français", "english": "French"]],
    ] {
      try JSONSerialization.data(withJSONObject: invalid).write(to: file)
      #expect(throws: (any Error).self) { try LanguageCatalog.load(from: file) }
    }
    try Data(repeating: 32, count: 150_000).write(to: file)
    #expect(throws: (any Error).self) { try LanguageCatalog.load(from: file) }
  }.value
}

private func removeDesignFixture(_ url: URL) {
  do { try FileManager.default.removeItem(at: url) } catch {
    fputs("Design fixture cleanup failed: \(error)\n", stderr)
  }
}
