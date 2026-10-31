import Foundation

public enum DictationOutputStyle: String, Codable, CaseIterable, Sendable {
  case verbatim, lightlyCleaned
  public var title: String { self == .verbatim ? "Verbatim" : "Lightly cleaned" }
}
