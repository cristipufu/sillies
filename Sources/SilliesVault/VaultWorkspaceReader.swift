import Foundation
import SilliesCore
import SilliesPersistence

/// Interactive reads cannot occupy the actor which owns capture saves and background jobs.
actor VaultWorkspaceReader {
  private let directory: URL
  private var database: VaultDatabase?

  init(directory: URL) { self.directory = directory }

  private func storage() throws -> VaultDatabase {
    if let database { return database }
    let opened = try VaultDatabase(reading: directory)
    database = opened
    return opened
  }

  func page(_ query: VaultWorkspaceQuery, after cursor: VaultWorkspaceCursor?) async throws
    -> VaultWorkspacePage
  {
    var position = cursor
    while true {
      try Task.checkCancellation()
      let page = try storage().workspacePage(query, after: position)
      guard page.records.isEmpty, let next = page.next else { return page }
      position = next
      await Task.yield()
    }
  }

  func header(id: UUID) throws -> VaultDocumentHeader? {
    try Task.checkCancellation()
    return try storage().documentHeader(id: id)
  }
  func search(_ request: VaultSearchRequest) throws -> [VaultSearchMatch] {
    try Task.checkCancellation()
    return try storage().search(request)
  }

  func section(_ location: VaultBlockLocation) throws -> VaultSectionPage {
    try storage().sectionPage(location)
  }

  func revision(_ location: VaultBlockLocation) throws -> UUID? {
    try Task.checkCancellation()
    return try storage().sectionRevision(location)
  }

  func sections(recordID: UUID) throws -> [VaultDocumentSection] {
    try Task.checkCancellation()
    return try storage().sectionKinds(recordID: recordID)
  }
  func facets(_ kind: VaultSourceFacet.Kind, matching text: String) throws -> [VaultSourceFacet] {
    try Task.checkCancellation()
    return try storage().sourceFacets(kind, matching: text)
  }
  func sourceLocation(_ reference: VaultSourceReference) throws -> VaultBlockLocation? {
    try Task.checkCancellation()
    return try storage().sourceLocation(reference)
  }
  func matchingPassages(recordID: UUID, query: VaultWorkspaceQuery) throws -> [VaultPassageMatch] {
    try storage().matchingPassages(recordID: recordID, query: query)
  }
  func bookmarks(id: UUID) throws -> [VaultRecordingBookmark] {
    try Task.checkCancellation()
    return try storage().recordingBookmarks(id: id)
  }
  func fileReferences(id: UUID) throws -> [VaultFileReference] {
    try Task.checkCancellation()
    return try storage().fileReferences(id: id)
  }
  func transcriptLocation(id: UUID, seconds: Double) throws -> VaultBlockLocation? {
    try Task.checkCancellation()
    return try storage().transcriptLocation(id: id, seconds: seconds)
  }
}
