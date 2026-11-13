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
  func evidenceLocation(_ passage: VaultEvidencePassage) throws -> VaultBlockLocation? {
    try Task.checkCancellation()
    return try storage().evidenceLocation(passage)
  }
  func searchEvidence(_ match: VaultSearchMatch, query: String, maximumCharacters: Int) throws
    -> VaultEvidencePassage?
  {
    try Task.checkCancellation()
    guard let location = match.location,
      ![.title, .labels, .files].contains(location.section),
      let block = try storage().sectionPage(location).blocks.first
    else { return nil }
    let text: String
    let offset: Int
    if let range = block.text.range(of: match.excerpt), !match.excerpt.isEmpty {
      text = String(match.excerpt.prefix(maximumCharacters))
      offset = block.text.unicodeScalars.distance(from: block.text.startIndex, to: range.lowerBound)
    } else {
      let source = VaultRecordPassage.Source(
        sections: [(location.section, block.text)], title: match.documentTitle ?? "")
      let passage = try VaultRecordPassage.select(
        in: source, query: query, maximumCharacters: maximumCharacters)
      text = passage.text
      let start = block.text.index(block.text.startIndex, offsetBy: passage.coverage.startOffset)
      offset = block.text.unicodeScalars.distance(from: block.text.startIndex, to: start)
    }
    return .init(block: block, scalarOffset: offset, text: text)
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
