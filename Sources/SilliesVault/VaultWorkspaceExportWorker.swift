import Foundation
import SilliesCore
import SilliesPersistence

/// Export has its own reader; browsing and capture writes do not queue behind file copies.
actor VaultWorkspaceExportWorker {
  private let directory: URL
  private var reader: VaultDatabase?
  init(directory: URL) { self.directory = directory }

  func exportText(_ text: String, to destination: URL) throws -> URL {
    guard !text.isEmpty, text.unicodeScalars.count <= VaultTextBlocks.maximumEditableScalars else {
      throw VaultEditingError.invalidValue
    }
    try Task.checkCancellation()
    let file = destination.appendingPathComponent("Sillies selection \(UUID().uuidString).md")
    try Data(text.utf8).write(to: file, options: .atomic)
    return file
  }

  func export(
    _ selection: VaultExportSelection, to destination: URL,
    prepare: @Sendable (UUID) async throws -> Void
  ) async throws -> Int {
    if reader == nil { reader = try VaultDatabase(reading: directory) }
    guard let reader else { throw CocoaError(.fileReadUnknown) }
    switch selection {
    case .records(let ids):
      var completed = 0
      for id in ids {
        try Task.checkCancellation()
        try await prepare(id)
        guard let header = try reader.documentHeader(id: id) else { continue }
        try await export(header, to: destination, reader: reader)
        completed += 1
      }
      return completed
    case .all:
      var cursor: VaultWorkspaceCursor?
      var completed = 0
      repeat {
        try Task.checkCancellation()
        let page = try reader.workspacePage(.init(), after: cursor)
        for header in page.records {
          try await prepare(header.id)
          try await export(header, to: destination, reader: reader)
          completed += 1
        }
        cursor = page.next
      } while cursor != nil
      return completed
    }
  }

  private func export(_ header: VaultDocumentHeader, to destination: URL, reader: VaultDatabase)
    async throws
  {
    let writer = try VaultDocumentExportWriter(
      sourceDirectory: directory, destination: destination, header: header)
    do {
      let sections = try reader.sectionKinds(recordID: header.id).filter {
        $0 != .title && $0 != .labels
      }
      for section in sections {
        try writer.beginSection(section)
        var ordinal: Int? = 0
        let location = VaultBlockLocation(recordID: header.id, section: section)
        let revision = try reader.sectionRevision(location)
        while let start = ordinal {
          try Task.checkCancellation()
          let page = try reader.sectionPage(
            .init(recordID: header.id, section: section, ordinal: start))
          guard page.blocks.allSatisfy({ $0.revision == revision }) else {
            throw VaultEditingError.revisionConflict
          }
          for block in page.blocks { try writer.append(block.text) }
          ordinal = page.nextOrdinal
          await Task.yield()
        }
        guard try reader.sectionRevision(location) == revision else {
          throw VaultEditingError.revisionConflict
        }
      }
      guard try reader.documentHeader(id: header.id) == header else {
        throw VaultEditingError.revisionConflict
      }
      _ = try writer.finish()
    } catch {
      writer.abandon()
      throw error
    }
  }
}
