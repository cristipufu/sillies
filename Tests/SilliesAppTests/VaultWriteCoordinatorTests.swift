import AppKit
import SilliesCore
import SilliesPersistence
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
    directory: URL(fileURLWithPath: "/unused"), queue: .init(label: "test.vault.commit"),
    commit: { request in saved.withLock { $0.append(request.records.first?.summary ?? "") } })
  var record = writeFixtureRecord()
  for value in 0..<2_000 {
    record.summary = "Revision \(value)"
    writer.save([record])
    #expect(writer.pendingSnapshotCount <= 2)
  }
  await withCheckedContinuation { continuation in writer.flush { continuation.resume() } }
  #expect(saved.withLock { $0 } == ["Revision 1999"])
  #expect(writer.pendingSnapshotCount == 0)
}

@Test @MainActor func vaultWriteBurstDuringAnActiveCommitRetainsOnlyTheNewestPendingSnapshot()
  async throws
{
  let gate = DispatchSemaphore(value: 0)
  defer { gate.signal() }
  let saved = Mutex<[String]>([])
  let writer = VaultWriteCoordinator(
    directory: URL(fileURLWithPath: "/unused"), queue: .init(label: "test.vault.slow-commit"),
    commit: { request in
      let first = saved.withLock { values in
        values.append(request.records.first?.summary ?? "")
        return values.count == 1
      }
      if first, gate.wait(timeout: .now() + 3) != .success { throw CocoaError(.fileWriteUnknown) }
    })
  var record = writeFixtureRecord()
  record.summary = "Original"
  writer.save([record])
  let deadline = ContinuousClock.now.advanced(by: .seconds(2))
  while saved.withLock({ $0.isEmpty }), ContinuousClock.now < deadline {
    try await Task.sleep(for: .milliseconds(1))
  }
  #expect(saved.withLock { $0 } == ["Original"])
  for value in 0..<1_000 {
    record.summary = "Revision \(value)"
    writer.save([record])
    #expect(writer.pendingSnapshotCount == 2)
  }
  gate.signal()
  await withCheckedContinuation { continuation in writer.flush { continuation.resume() } }
  #expect(saved.withLock { $0 } == ["Original", "Revision 999"])
  #expect(writer.pendingSnapshotCount == 0)
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
  #expect(try SessionRecordRepository(directory: directory).load().isEmpty)
  try FileManager.default.removeItem(at: destination)
  store.retrySaving()
  await store.flush()
  #expect(store.persistenceError == nil)
  #expect(try Data(contentsOf: destination) == png)
  #expect(try SessionRecordRepository(directory: directory).load().first?.imageFilename == filename)
}
