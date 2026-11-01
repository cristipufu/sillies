import Foundation

/// Discovers bundled JSON contributions once on a worker. Theme files never execute code.
package enum ThemeCatalog {
  package static let defaultID = "sillies"
  private static let maximumThemes = 128
  private static let maximumThemeBytes = 16 * 1_024

  package static func loadBundled() throws -> [ThemeDefinition] {
    guard let directory = Bundle.module.url(forResource: "Themes", withExtension: nil) else {
      throw ThemeCatalogFailure.invalid(String(localized: "The bundled theme folder is missing."))
    }
    return try load(from: directory)
  }

  package static func load(from directory: URL) throws -> [ThemeDefinition] {
    dispatchPrecondition(condition: .notOnQueue(.main))
    let files = try FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
      options: [.skipsHiddenFiles]
    )
    .filter { $0.pathExtension == "json" }
    guard !files.isEmpty, files.count <= maximumThemes else {
      throw ThemeCatalogFailure.invalid(
        String(localized: "A catalog needs between 1 and \(maximumThemes) themes."))
    }
    var themes: [ThemeDefinition] = []
    var identifiers: Set<String> = []
    for file in files {
      let theme = try read(file)
      guard file.deletingPathExtension().lastPathComponent == theme.id,
        identifiers.insert(theme.id).inserted
      else {
        throw ThemeCatalogFailure.invalid(
          String(localized: "Theme filenames must match unique theme IDs."))
      }
      themes.append(theme)
    }
    return themes.sorted { ($0.order, $0.id) < ($1.order, $1.id) }
  }

  private static func read(_ file: URL) throws -> ThemeDefinition {
    let metadata = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    guard metadata.isRegularFile == true, metadata.isSymbolicLink != true else {
      throw ThemeCatalogFailure.invalid(
        String(localized: "Theme contributions must be regular JSON files."))
    }
    let handle = try FileHandle(forReadingFrom: file)
    let data: Data
    do {
      data = try handle.read(upToCount: maximumThemeBytes + 1) ?? Data()
      try handle.close()
    } catch {
      do { try handle.close() } catch { fputs("Theme file close failed: \(error)\n", stderr) }
      throw error
    }
    guard data.count <= maximumThemeBytes else {
      throw ThemeCatalogFailure.invalid(
        String(localized: "A theme exceeds the \(maximumThemeBytes)-byte limit."))
    }
    return try JSONDecoder().decode(ThemeDefinition.self, from: data)
  }
}
