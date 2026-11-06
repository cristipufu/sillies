import Foundation
import SilliesCore
import SilliesPersistence

extension ConversationLibrary: ConversationExporting {
  package func exportConversation(
    _ request: ConversationExportRequest, to destination: URL,
    progress: @escaping @Sendable (Int) async -> Void
  ) async throws -> Int {
    try validateExportDestination(destination)
    let latest = try page(.init(handle: request.handle, limit: 1))
    let boundary = latest.entries.last?.sequence ?? 0
    let writer = try ConversationMarkdownWriter(
      destination: destination, companionName: request.companionName)
    defer { writer.discard() }
    var cursor: Int64 = 0
    var count = 0
    while cursor < boundary {
      try Task.checkCancellation()
      let next = try page(.init(handle: request.handle, position: .after(cursor)))
      let entries = next.entries.filter { $0.sequence <= boundary }
      guard let last = entries.last, last.sequence > cursor else {
        throw ConversationStorageError.changed
      }
      try writer.append(entries)
      cursor = last.sequence
      count += entries.count
      await progress(count)
      // A large export yields between pages to capture, saves and cancellation.
      await Task.yield()
    }
    try storage().validateForExport(request.handle)
    try writer.finish()
    return count
  }

  private func validateExportDestination(_ destination: URL) throws {
    let reserved = [
      ConversationDatabase.filename, ConversationDatabase.filename + "-wal",
      ConversationDatabase.filename + "-shm",
    ]
    let target = destination.resolvingSymlinksInPath().standardizedFileURL
    if reserved.contains(target.lastPathComponent),
      target.deletingLastPathComponent() == directory.resolvingSymlinksInPath().standardizedFileURL
    {
      throw CocoaError(.fileWriteInvalidFileName)
    }
  }
}
