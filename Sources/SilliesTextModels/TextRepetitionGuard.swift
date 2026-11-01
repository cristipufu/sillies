import Foundation

/// Detects long consecutive cycles in any language, not specific words or factual claims.
package enum TextRepetitionGuard {
  private static let minimumRepetitions = 6
  private static let minimumRepeatedCharacters = 120
  private static let maximumPeriod = 160
  private static let inspectedCharacters = 4_096

  package static func containsLoop(_ text: String) -> Bool {
    let characters = Array(
      text.suffix(inspectedCharacters).lowercased().unicodeScalars.filter {
        !CharacterSet.whitespacesAndNewlines.contains($0)
      })
    guard characters.count >= minimumRepeatedCharacters else { return false }
    let longestPeriod = min(maximumPeriod, characters.count / minimumRepetitions)
    for period in 1...longestPeriod {
      let requiredMatches = max(
        (minimumRepetitions - 1) * period, minimumRepeatedCharacters - period)
      var matches = 0
      for index in period..<characters.count {
        matches = characters[index] == characters[index - period] ? matches + 1 : 0
        if matches >= requiredMatches { return true }
      }
    }
    return false
  }
}
