import Foundation

/// Small build-generated metadata; translation tables stay in native .lproj resources.
package struct InterfaceLanguage: Codable, Equatable, Sendable, Identifiable {
  package let code: String
  package let language: String
  package let english: String
  package var id: String { code }
}

package enum LanguageCatalog {
  private static let maximumBytes = 128 * 1_024
  private static let maximumLanguages = 256

  package static func load(from file: URL) throws -> [InterfaceLanguage] {
    dispatchPrecondition(condition: .notOnQueue(.main))
    let metadata = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    guard metadata.isRegularFile == true, metadata.isSymbolicLink != true else {
      throw CocoaError(.fileReadCorruptFile)
    }
    let handle = try FileHandle(forReadingFrom: file)
    defer {
      do { try handle.close() } catch {
        fputs("Language metadata close failed: \(error)\n", stderr)
      }
    }
    let bytes = try handle.read(upToCount: maximumBytes + 1) ?? Data()
    guard bytes.count <= maximumBytes else { throw CocoaError(.fileReadCorruptFile) }
    let languages = try JSONDecoder().decode([InterfaceLanguage].self, from: bytes)
    guard (1...maximumLanguages).contains(languages.count),
      Set(languages.map(\.code)).count == languages.count,
      languages.contains(where: { $0.code == "en" }), languages.allSatisfy(isValid)
    else { throw CocoaError(.fileReadCorruptFile) }
    return languages.sorted {
      $0.language.localizedStandardCompare($1.language) == .orderedAscending
    }
  }

  private static func isValid(_ language: InterfaceLanguage) -> Bool {
    language.code.range(of: "^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$", options: .regularExpression)
      == (language.code.startIndex..<language.code.endIndex)
      && language.code.count <= 35
      && [language.language, language.english].allSatisfy {
        !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 80
          && $0.rangeOfCharacter(from: .controlCharacters) == nil
      }
  }
}
