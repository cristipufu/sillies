import Foundation

public struct SearchIndexProgress: Equatable, Sendable {
  public let processed: Int
  public let searchable: Int
  public let total: Int
  public init(processed: Int, searchable: Int, total: Int) {
    self.processed = processed
    self.searchable = searchable
    self.total = total
  }
}
