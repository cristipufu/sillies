import Foundation
import SilliesCore

public struct VaultPageRequest: Sendable {
  public static let maximumPageSize = 200
  public let search: SessionRecordSearch
  public let after: VaultPageCursor?
  public let limit: Int
  public init(
    search: SessionRecordSearch = .init(kind: nil, query: ""), after: VaultPageCursor? = nil,
    limit: Int = maximumPageSize
  ) {
    self.search = search
    self.after = after
    self.limit = max(1, min(limit, Self.maximumPageSize))
  }
}

public struct VaultPage: Sendable {
  public let records: [SessionRecordHeader]
  public let total: Int
  public let nextCursor: VaultPageCursor?
  public init(records: [SessionRecordHeader], total: Int, nextCursor: VaultPageCursor?) {
    self.records = records
    self.total = total
    self.nextCursor = nextCursor
  }
}

public enum VaultDeletion: Sendable {
  case records(Set<UUID>)
  case all
}

public enum VaultRecordWrite: Sendable {
  case insert(SessionRecord)
  case update(SessionRecord)
  public var record: SessionRecord {
    switch self {
    case .insert(let record), .update(let record): record
    }
  }
}

public struct VaultSnapshot: Sendable {
  public let page: VaultPage
  public let eligibleRetentionCount: Int
  public let removedRecordIDs: Set<UUID>
  public init(page: VaultPage, eligibleRetentionCount: Int, removedRecordIDs: Set<UUID> = []) {
    self.page = page
    self.eligibleRetentionCount = eligibleRetentionCount
    self.removedRecordIDs = removedRecordIDs
  }
}

public struct VaultMutation: Sendable {
  public let records: [VaultRecordWrite]
  public let deletion: VaultDeletion
  public let retention: VaultRetentionPolicy
  public let attachments: [VaultAttachment]
  public init(
    records: [VaultRecordWrite] = [], deletion: VaultDeletion = .records([]),
    retention: VaultRetentionPolicy = .keepAll, attachments: [VaultAttachment] = []
  ) {
    self.records = records
    self.deletion = deletion
    self.retention = retention
    self.attachments = attachments
  }
}

public struct VaultStorageMetrics: Sendable {
  public internal(set) var decodedBodyBytes = 0
  public internal(set) var encodedBodyBytes = 0
  public internal(set) var loadedBodies = 0
  public internal(set) var pageReads = 0
  public internal(set) var loadedHeaders = 0
  public internal(set) var writtenBodies = 0
  public internal(set) var indexedDocuments = 0
  public init() {}
}

public struct VaultAttachment: Sendable {
  public let filename: String
  public let data: Data
  public init(filename: String, data: Data) {
    self.filename = filename
    self.data = data
  }
}

public struct VaultStorageError: Error, LocalizedError {
  public let message: String
  public init(message: String) { self.message = message }
  public var errorDescription: String? { message }
}
