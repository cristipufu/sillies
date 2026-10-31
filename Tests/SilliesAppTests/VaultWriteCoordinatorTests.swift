import AppKit
import SilliesCore
import SilliesPersistence
import SilliesVault
import Synchronization
import Testing

@testable import SilliesApp

private func writeFixtureRecord() -> SessionRecord {
  SessionRecord(
    kind: .snap,
    origin: .init(
      characterID: "mochi", characterName: "Mochi", source: .init(appName: "Fixture")))
}

@Test @MainActor func vaultWriteBurstCoalescesToTheLatestSnapshot() async {
  let saved = Mutex<[String]>([])
  let writer = VaultWriteCoordinator(
    library: VaultLibrary(directory: URL(fileURLWithPath: "/unused")),
    commit: { request in
      saved.withLock { $0.append(request.writes.values.first?.record.summary ?? "") }
      return emptySnapshot()
    })
  writer.activate()
  var record = writeFixtureRecord()
  for value in 0..<2_000 {
    record.summary = "Revision \(value)"
    writer.save(.insert(record))
    #expect(writer.pendingBatchCount <= 2)
  }
  await withCheckedContinuation { continuation in writer.flush { continuation.resume() } }
  #expect(saved.withLock { $0 } == ["Revision 1999"])
  #expect(writer.pendingBatchCount == 0)
}

@Test @MainActor func vaultWriteBurstDuringAnActiveCommitRetainsOnlyTheNewestPendingSnapshot()
  async throws
{
  let gate = CommitBarrier()
  defer { Task { await gate.release() } }
  let saved = Mutex<[String]>([])
  let writer = VaultWriteCoordinator(
    library: VaultLibrary(directory: URL(fileURLWithPath: "/unused")),
    commit: { request in
      let first = saved.withLock { values in
        values.append(request.writes.values.first?.record.summary ?? "")
        return values.count == 1
      }
      if first { await gate.wait() }
      return emptySnapshot()
    })
  writer.activate()
  var record = writeFixtureRecord()
  record.summary = "Original"
  writer.save(.insert(record))
  let deadline = ContinuousClock.now.advanced(by: .seconds(2))
  while saved.withLock({ $0.isEmpty }), ContinuousClock.now < deadline {
    try await Task.sleep(for: .milliseconds(1))
  }
  #expect(saved.withLock { $0 } == ["Original"])
  for value in 0..<1_000 {
    record.summary = "Revision \(value)"
    writer.save(.insert(record))
    #expect(writer.pendingBatchCount == 2)
  }
  await gate.release()
  await withCheckedContinuation { continuation in writer.flush { continuation.resume() } }
  #expect(saved.withLock { $0 } == ["Original", "Revision 999"])
  #expect(writer.pendingBatchCount == 0)
}

@Test @MainActor func vaultRetryResavesTheOriginalScreenshotBeforeClearingItsError() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let record = writeFixtureRecord()
  let filename = "\(record.id.uuidString).png"
  let destination = directory.appendingPathComponent(filename)
  try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
  // An occupied attachment path fails the image write while the metadata directory is writable.
  try Data([7]).write(to: destination.appendingPathComponent("occupied"))
  let context = try #require(
    CGContext(
      data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
  )
  let image = try #require(context.makeImage())
  let encoded = await Task.detached { VaultImageCodec.encodePNGData(from: image) }.value
  let png = try #require(encoded)
  let store = SessionVaultStore(directory: directory)
  await store.waitUntilLoaded()
  store.add(record, image: image, pngData: png)
  await store.flush()
  #expect(store.persistenceError != nil)
  #expect(try await store.library.page(.init()).records.isEmpty)
  try FileManager.default.removeItem(at: destination)
  store.retrySaving()
  await store.flush()
  #expect(store.persistenceError == nil)
  #expect(try Data(contentsOf: destination) == png)
  #expect(try await store.library.record(id: record.id)?.imageFilename == filename)
}

private func emptySnapshot() -> VaultSnapshot {
  .init(page: .init(records: [], total: 0, nextCursor: nil), eligibleRetentionCount: 0)
}

@Test @MainActor func vaultDeletionRemainsVisibleWhileItsCommitIsInFlight() async throws {
  let gate = CommitBarrier()
  let writer = VaultWriteCoordinator(
    library: VaultLibrary(directory: URL(fileURLWithPath: "/unused")),
    commit: { _ in
      await gate.wait()
      return emptySnapshot()
    })
  writer.activate()
  let id = UUID()
  writer.remove(id)
  writer.flush {}
  #expect(writer.isRemoved(id))
  #expect(writer.record(id) == nil)
  await gate.release()
  await withCheckedContinuation { continuation in writer.flush { continuation.resume() } }

  writer.clear()
  writer.flush {}
  #expect(writer.isRemoved(UUID()))
  let new = writeFixtureRecord()
  writer.save(.insert(new))
  #expect(!writer.isRemoved(new.id))
  #expect(writer.record(new.id)?.id == new.id)
  await withCheckedContinuation { continuation in writer.flush { continuation.resume() } }
}

private actor CommitBarrier {
  private var released = false
  private var waiter: CheckedContinuation<Void, Never>?
  func wait() async {
    if released { return }
    await withCheckedContinuation { waiter = $0 }
  }
  func release() {
    released = true
    waiter?.resume()
    waiter = nil
  }
}
