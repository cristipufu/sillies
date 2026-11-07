import Foundation
import SilliesCore
import SilliesPersistence

extension VaultLibrary {
  package nonisolated func exportText(_ text: String, to destination: URL) async throws -> URL {
    try await workspaceExporter.exportText(text, to: destination)
  }
  package nonisolated func fileReferences(id: UUID) async throws -> [VaultFileReference] {
    try await documentReader.fileReferences(id: id)
  }
  package func relink(_ reference: VaultFileReference, to url: URL) throws {
    try storage().relink(reference, to: url)
    searchRevision = UUID()
    scheduleIndex()
  }
  package nonisolated func matchingPassages(recordID: UUID, query: VaultWorkspaceQuery) async throws
    -> [VaultPassageMatch]
  {
    try await assistantReader.matchingPassages(recordID: recordID, query: query)
  }
  package nonisolated func sourceLocation(_ reference: VaultSourceReference) async throws
    -> VaultBlockLocation?
  {
    try await documentReader.sourceLocation(reference)
  }
  package func appendQuote(_ quote: VaultQuotedPassage, to id: UUID, at date: Date) throws
    -> VaultBlockLocation
  {
    let location = try storage().appendQuote(quote, to: id, at: date)
    cache.remove(id)
    searchRevision = UUID()
    scheduleIndex()
    return location
  }
  package nonisolated func sourceFacets(_ kind: VaultSourceFacet.Kind, matching text: String)
    async throws -> [VaultSourceFacet]
  {
    try await documentReader.facets(kind, matching: text)
  }
  package func editDocuments(ids: Set<UUID>, edit: VaultDocumentEdit, at date: Date) throws {
    try storage().editDocuments(ids: ids, edit: edit, at: date)
    for id in ids { cache.remove(id) }
    searchRevision = UUID()
    scheduleIndex()
  }
  package nonisolated func workspacePage(
    _ query: VaultWorkspaceQuery, after cursor: VaultWorkspaceCursor? = nil
  ) async throws -> VaultWorkspacePage {
    return try await workspaceReader.page(query, after: cursor)
  }

  package nonisolated func documentHeader(id: UUID) async throws -> VaultDocumentHeader? {
    return try await documentReader.header(id: id)
  }

  package nonisolated func sectionPage(_ location: VaultBlockLocation) async throws
    -> VaultSectionPage
  {
    return try await documentReader.section(location)
  }

  package nonisolated func sectionRevision(_ location: VaultBlockLocation) async throws -> UUID? {
    return try await documentReader.revision(location)
  }

  package nonisolated func sectionKinds(recordID: UUID) async throws -> [VaultDocumentSection] {
    return try await documentReader.sections(recordID: recordID)
  }

  package func editDocument(id: UUID, edit: VaultDocumentEdit, at date: Date) throws
    -> VaultDocumentHeader
  {
    let header = try storage().editDocument(id: id, edit: edit, at: date)
    cache.remove(id)
    searchRevision = UUID()
    scheduleIndex()
    return header
  }

  package func editText(_ edit: VaultTextEdit, at date: Date) throws -> UUID {
    let revision = try storage().editText(edit, at: date)
    cache.remove(edit.location.recordID)
    searchRevision = UUID()
    scheduleIndex()
    return revision
  }

  package func collections() throws -> [VaultCollection] { try storage().collections() }
  package func saveCollection(_ collection: VaultCollection) throws {
    try storage().saveCollection(collection)
  }
  package func removeCollection(id: UUID) throws { try storage().removeCollection(id: id) }
  package func savedSearches() throws -> [VaultSavedSearch] { try storage().savedSearches() }
  package func saveSearch(_ search: VaultSavedSearch) throws { try storage().saveSearch(search) }
  package func removeSavedSearch(id: UUID) throws { try storage().removeSavedSearch(id: id) }

  package func createDocument(
    record: SessionRecord, metadata: VaultDocumentMetadata, notes: String = ""
  ) throws -> VaultDocumentHeader {
    let header = try storage().createDocument(record: record, metadata: metadata, notes: notes)
    searchRevision = UUID()
    scheduleIndex()
    return header
  }

  /// One archived record per call lets the owning producer yield, pause, and resume.
  package func prepareContentSlice() throws -> Bool { try storage().prepareNextContent() }
  package func pendingLink() throws -> VaultDocumentHeader? { try storage().pendingLink() }
  package func saveLinkPreview(_ preview: VaultLinkPreview, id: UUID) throws -> VaultDocumentHeader?
  {
    let header = try storage().saveLinkPreview(preview, id: id, at: Date())
    cache.remove(id)
    searchRevision = UUID()
    scheduleIndex()
    return header
  }
}
