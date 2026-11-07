import Foundation
import SilliesCore
import SilliesPersistence
import SilliesVault

enum VaultLifecycleProbe {
  static func drain(_ library: VaultLibrary, seconds: Double) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
    await library.resumeCleanup()
    var pageTimes: [Double] = []
    do {
      while true {
        let (progress, failure) = try await library.cleanupStatus()
        guard failure == nil else { throw ProbeFailure.cleanup }
        if !progress.isPending || ContinuousClock.now >= deadline { break }
        let started = ContinuousClock.now
        _ = try await library.workspacePage(.init())
        pageTimes.append(VaultScaleBenchmark.milliseconds(started.duration(to: .now)))
        try await Task.sleep(for: .milliseconds(100))
      }
      await library.stopCleanup()
      let (progress, failure) = try await library.cleanupStatus()
      guard failure == nil else { throw ProbeFailure.cleanup }
      try VaultScaleBenchmark.emit(
        CleanupResult(
          complete: !progress.isPending, removed: progress.removedRecords,
          visible: try await library.snapshot().page.total, pageMilliseconds: pageTimes))
    } catch {
      await library.stopCleanup()
      throw error
    }
  }

  static func backup(_ library: VaultLibrary, directory: URL) async throws {
    let destination = backupDirectory(directory)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
    let expected = try await library.snapshot().page.total
    let started = ContinuousClock.now
    let archive = try await library.backup(to: destination)
    let duration = VaultScaleBenchmark.milliseconds(started.duration(to: .now))
    let reopened = VaultLibrary(directory: archive)
    let actual = try await reopened.snapshot().page.total
    guard actual == expected else { throw ProbeFailure.recordCount }
    let receipt = BackupReceipt(archive: archive, records: actual, milliseconds: duration)
    try JSONEncoder().encode(receipt).write(to: receiptURL(directory), options: .atomic)
    try VaultScaleBenchmark.emit(receipt)
  }

  static func restore(directory: URL) async throws {
    let receipt = try JSONDecoder().decode(
      BackupReceipt.self, from: Data(contentsOf: receiptURL(directory)))
    let destination = directory.appendingPathExtension("restored")
    guard !FileManager.default.fileExists(atPath: destination.path) else {
      throw ProbeFailure.existingDestination
    }
    let started = ContinuousClock.now
    let preparing = VaultLibrary(directory: destination)
    try await preparing.prepareRestore(from: receipt.archive)
    let preparation = VaultScaleBenchmark.milliseconds(started.duration(to: .now))
    try VaultScaleBenchmark.emit(Phase(name: "prepared", milliseconds: preparation))
    let launch = ContinuousClock.now
    let restored = VaultLibrary(directory: destination, opening: .applicationLaunch)
    let records = try await restored.snapshot().page.total
    guard records == receipt.records else { throw ProbeFailure.recordCount }
    let launchMilliseconds = VaultScaleBenchmark.milliseconds(launch.duration(to: .now))
    try VaultScaleBenchmark.emit(Phase(name: "activated", milliseconds: launchMilliseconds))
    let files = try compareAttachments(source: receipt.archive, destination: destination)
    let sampledRecords = try await compareContent(source: receipt.archive, restored: restored)
    try VaultScaleBenchmark.emit(
      RestoreResult(
        records: records, preparationMilliseconds: preparation,
        launchMilliseconds: launchMilliseconds, verifiedFiles: files,
        verifiedContentRecords: sampledRecords, directory: destination))
  }

  static func verifyRestore(directory: URL) async throws {
    let receipt = try JSONDecoder().decode(
      BackupReceipt.self, from: Data(contentsOf: receiptURL(directory)))
    let destination = directory.appendingPathExtension("restored")
    let restored = VaultLibrary(directory: destination, opening: .applicationLaunch)
    let started = ContinuousClock.now
    let records = try await restored.snapshot().page.total
    guard records == receipt.records else { throw ProbeFailure.recordCount }
    try VaultScaleBenchmark.emit(
      Phase(
        name: "reopened", milliseconds: VaultScaleBenchmark.milliseconds(started.duration(to: .now))
      ))
    let files = try compareAttachments(source: receipt.archive, destination: destination)
    try VaultScaleBenchmark.emit(
      Phase(
        name: "filesVerified",
        milliseconds: VaultScaleBenchmark.milliseconds(started.duration(to: .now))))
    let sample = try await compareContent(source: receipt.archive, restored: restored)
    try VaultScaleBenchmark.emit(
      RestoreResult(
        records: records, preparationMilliseconds: nil, launchMilliseconds: nil,
        verifiedFiles: files, verifiedContentRecords: sample, directory: destination))
  }

  private static func compareContent(source: URL, restored: VaultLibrary) async throws -> Int {
    let started = ContinuousClock.now
    let original = VaultLibrary(directory: source, cacheBytes: 0)
    let newest = try await original.workspacePage(.init())
    let oldest = try await original.workspacePage(.init(ordering: .oldest))
    let sample = Set((newest.records.prefix(10) + oldest.records.prefix(10)).map(\.id))
    try VaultScaleBenchmark.emit(
      Phase(
        name: "sampleSelected",
        milliseconds: VaultScaleBenchmark.milliseconds(started.duration(to: .now))))
    for id in sample {
      guard try await original.record(id: id) == restored.record(id: id) else {
        throw ProbeFailure.content
      }
      for section in try await original.sectionKinds(recordID: id) {
        var location = VaultBlockLocation(recordID: id, section: section, ordinal: 0)
        while true {
          let expected = try await original.sectionPage(location)
          let actual = try await restored.sectionPage(location)
          guard actual.blocks == expected.blocks, actual.nextOrdinal == expected.nextOrdinal,
            actual.previousOrdinal == expected.previousOrdinal
          else { throw ProbeFailure.content }
          guard let next = expected.nextOrdinal else { break }
          location = .init(recordID: id, section: section, ordinal: next)
        }
      }
    }
    return sample.count
  }

  private static func compareAttachments(source: URL, destination: URL) throws -> Int {
    let snapshot = try VaultDatabase(reading: source)
    var recordID: UUID?
    var count = 0
    while let batch = try snapshot.backupAttachments(after: recordID) {
      for name in batch.filenames {
        let original = try VaultFileStorage(directory: source).attachmentURL(for: name)
        let restored = try VaultFileStorage(directory: destination).attachmentURL(for: name)
        guard FileManager.default.contentsEqual(atPath: original.path, andPath: restored.path)
        else {
          throw ProbeFailure.attachment
        }
        count += 1
      }
      recordID = batch.lastRecordID
    }
    return count
  }

  private static func backupDirectory(_ source: URL) -> URL {
    source.appendingPathExtension("backups")
  }
  private static func receiptURL(_ source: URL) -> URL {
    source.appendingPathExtension("backup-receipt.json")
  }
  private struct BackupReceipt: Codable {
    let archive: URL
    let records: Int
    let milliseconds: Double
  }
  private struct CleanupResult: Encodable {
    let complete: Bool
    let removed: Int
    let visible: Int
    let pageMilliseconds: [Double]
  }
  private struct RestoreResult: Encodable {
    let records: Int
    let preparationMilliseconds: Double?
    let launchMilliseconds: Double?
    let verifiedFiles: Int
    let verifiedContentRecords: Int
    let directory: URL
  }
  private struct Phase: Encodable {
    let name: String
    let milliseconds: Double
  }
  private enum ProbeFailure: Error {
    case cleanup, recordCount, attachment, content, existingDestination
  }
}
