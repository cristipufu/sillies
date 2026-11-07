import Foundation
import SilliesCore

public struct VaultWorkspaceCursor: Codable, Hashable, Sendable {
  public let value: Double
  public let id: UUID
  public init(value: Double, id: UUID) {
    self.value = value
    self.id = id
  }
}

public struct VaultWorkspacePage: Sendable {
  public static let maximumCount = 100
  public let records: [VaultDocumentHeader]
  public let next: VaultWorkspaceCursor?
  public init(records: [VaultDocumentHeader], next: VaultWorkspaceCursor?) {
    self.records = records
    self.next = next
  }
}
