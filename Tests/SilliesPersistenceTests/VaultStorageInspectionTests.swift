import Foundation
import SilliesPersistence
import Testing

@Test func vaultStorageCategoriesDoNotDependOnDirectoryURLSpelling() async throws {
  try await Task.detached {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer {
      do { try FileManager.default.removeItem(at: root) } catch {
        Issue.record("Storage fixture cleanup failed: \(error)")
      }
    }
    let cache = root.appendingPathComponent("index", isDirectory: true)
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    let payload = Data(repeating: 87, count: 64 * 1024)
    for file in [
      root.appendingPathComponent(VaultDatabase.filename),
      root.appendingPathComponent("capture.m4a"), cache.appendingPathComponent("vectors"),
      root.appendingPathComponent("conversations.sqlite"),
    ] {
      try payload.write(to: file)
    }
    let withSlash = URL(fileURLWithPath: root.path, isDirectory: true)
    let withoutSlash = URL(fileURLWithPath: root.path, isDirectory: false)
    let first = try VaultStorageInspection.measure(withSlash)
    let second = try VaultStorageInspection.measure(withoutSlash)
    #expect(first.databaseBytes > 0 && first.attachmentBytes > 0 && first.searchCacheBytes > 0)
    #expect(first.databaseBytes == second.databaseBytes)
    #expect(first.attachmentBytes == second.attachmentBytes)
    #expect(first.searchCacheBytes == second.searchCacheBytes)
    #expect(
      first.attachmentBytes == first.databaseBytes,
      "The separate conversation archive is not a capture attachment.")
  }.value
}
