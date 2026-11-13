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
  func savedLinks(id: UUID) throws -> [URL] {
    guard let header = try storage().documentHeader(id: id), header.metadata.trashedAt == nil else {
      return []
    }
    return try savedLinks(in: header)
  }

  private func savedLinks(in header: VaultDocumentHeader) throws -> [URL] {
    if let link = header.metadata.link { return [link.url] }
    guard let record = try record(id: header.id) else { return [] }
    return try VaultToolContent.links(in: record)
  }

  func reasoningDocument(id: UUID) throws -> VaultReasoningDocument? {
    let storage = try storage()
    try storage.prepareContent(id: id)
    guard let header = try storage.documentHeader(id: id), header.metadata.trashedAt == nil
    else { return nil }
    let kinds = try storage.sectionKinds(recordID: id)
    let captured: [VaultDocumentSection] = [.transcript, .screenshotText, .stash, .explanation]
    var selected = captured.filter { kinds.contains($0) }
    selected += [.notes, .linkText].filter { kinds.contains($0) }
    if selected.isEmpty, kinds.contains(.summary) { selected.append(.summary) }
    let sections = try selected.map { kind in
      (kind, try storage.sectionText(.init(recordID: id, section: kind)))
    }
    return try .init(
      header: header, content: .init(sections: sections, title: header.title),
      links: savedLinks(in: header))
  }

  func evidence(for passages: [VaultRecordPassage], in document: VaultReasoningDocument) throws
    -> [VaultEvidencePassage]
  {
    try passages.flatMap { passage in
      try passage.evidence(in: document.content) { section, bytes, text in
        try storage().evidence(
          recordID: document.header.id, section: section, bytes: bytes, expected: text)
      }
    }
  }
}
