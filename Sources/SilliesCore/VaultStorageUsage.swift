import Foundation

public struct VaultStorageUsage: Sendable {
  public var databaseBytes: Int64 = 0
  public var attachmentBytes: Int64 = 0
  public var searchCacheBytes: Int64 = 0
  public init() {}
}
