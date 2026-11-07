import Foundation
import SilliesCore

struct VaultReasoningDocument {
  let header: VaultDocumentHeader
  let content: VaultRecordPassage.Source
  let links: [URL]

  func source(excerpt: String) -> ChatSource {
    .init(
      VaultSearchMatch(header: header.source, excerpt: excerpt).located(in: header), links: links)
  }
}

extension VaultLibrary {
  func reasoningDocument(id: UUID) throws -> VaultReasoningDocument? {
    let storage = try storage()
    try storage.prepareContent(id: id)
    guard let header = try storage.documentHeader(id: id), header.metadata.trashedAt == nil,
      let record = try record(id: id)
    else { return nil }
    // Standalone notes already materialize their authored text for existing Stash consumers.
    let notes = header.metadata.kind == .capture ? try storage.authoredNotes(recordID: id) : ""
    return try .init(
      header: header, content: .init(record: record, notes: notes, title: header.title),
      links: header.metadata.link.map { [$0.url] } ?? VaultToolContent.links(in: record))
  }
}
