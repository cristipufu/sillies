import Foundation

public struct StashContents: Sendable {
  public let items: [String]
  public var summary: String { "Saved \(items.count) item(s)." }

  public init?(_ items: [String]) {
    let cleaned = items.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter {
      !$0.isEmpty
    }
    guard !cleaned.isEmpty else { return nil }
    self.items = cleaned
  }
}
