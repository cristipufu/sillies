import Foundation

public enum DictationOutputStyle: String, Codable, CaseIterable, Sendable {
  case verbatim, lightlyCleaned
  public var title: String {
    self == .verbatim ? String(localized: "Verbatim") : String(localized: "Lightly cleaned")
  }
}
