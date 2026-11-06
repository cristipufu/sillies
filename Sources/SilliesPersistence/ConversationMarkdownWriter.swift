import Foundation
import SilliesCore

/// Writes beside the destination, then atomically publishes only the completed export.
public final class ConversationMarkdownWriter {
  private let temporary: URL
  private let destination: URL
  private var file: FileHandle?
  private let formatter: ConversationMarkdownFormatter

  public init(destination: URL, companionName: String) throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    guard destination.isFileURL else { throw CocoaError(.fileWriteUnsupportedScheme) }
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    {
      throw CocoaError(.fileWriteInvalidFileName)
    }
    self.destination = destination
    formatter = ConversationMarkdownFormatter(companionName: companionName)
    temporary = destination.deletingLastPathComponent().appendingPathComponent(
      ".sillies-conversation-\(UUID().uuidString).tmp")
    guard
      FileManager.default.createFile(
        atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600])
    else {
      throw CocoaError(.fileWriteUnknown)
    }
    do {
      file = try FileHandle(forWritingTo: temporary)
      try write(formatter.heading)
    } catch {
      discard()
      throw error
    }
  }

  public func append(_ entries: [ConversationEntry]) throws {
    for entry in entries {
      try Task.checkCancellation()
      try write(formatter.message(entry))
    }
  }

  public func finish() throws {
    try Task.checkCancellation()
    try file?.synchronize()
    try file?.close()
    file = nil
    if FileManager.default.fileExists(atPath: destination.path) {
      _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
    } else {
      try FileManager.default.moveItem(at: temporary, to: destination)
    }
  }

  public func discard() {
    do { try file?.close() } catch { fputs("Conversation export close failed: \(error)\n", stderr) }
    file = nil
    guard FileManager.default.fileExists(atPath: temporary.path) else { return }
    do { try FileManager.default.removeItem(at: temporary) } catch {
      fputs("Conversation export cleanup failed: \(error)\n", stderr)
    }
  }

  private func write(_ text: String) throws {
    guard let file else { throw CocoaError(.fileWriteUnknown) }
    try file.write(contentsOf: Data(text.utf8))
  }
}
