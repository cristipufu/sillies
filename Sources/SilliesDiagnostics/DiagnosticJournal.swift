import Foundation
import OSLog

/// The actor owns all filesystem work. Only known file slots are read; no directory walks.
actor DiagnosticJournal {
  struct FileState {
    var bytes: Int
    let started: Date
  }
  let directory: URL
  let limits: DiagnosticLimits
  private let logger = Logger(subsystem: "app.sillies.macos", category: "diagnostics")
  private var files: [Int: FileState] = [:]
  private var isPrepared = false
  private(set) var discardedRecords = 0

  init(directory: URL, limits: DiagnosticLimits) {
    self.directory = directory
    self.limits = limits
  }

  func prepare(now: Date) throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    try limits.validate()
    if !isPrepared {
      try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
      try validateDirectory()
      if FileManager.default.fileExists(atPath: stagingURL.path) {
        try FileManager.default.removeItem(at: stagingURL)
      }
      files.removeAll()
      for index in 0..<limits.fileCount { try inspect(index) }
      isPrepared = true
    }
    try prune(now: now)
  }

  func append(_ records: [DiagnosticRecord], now: Date) throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    try prepare(now: now)
    let encoder = DiagnosticRecord.encoder()
    for record in records {
      var data = try encoder.encode(record)
      data.append(0x0A)
      guard data.count <= limits.recordBytes else { throw DiagnosticStorageError.recordTooLarge }
      if (files[0]?.bytes ?? 0) + data.count > limits.fileBytes { try rotate() }
      let file = url(0)
      if files[0] == nil {
        guard
          FileManager.default.createFile(
            atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
        else { throw DiagnosticStorageError.unavailable }
        files[0] = FileState(bytes: 0, started: record.timestamp)
      }
      let handle = try FileHandle(forWritingTo: file)
      do {
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.close()
      } catch {
        do { try handle.close() } catch { reportStorageFailure() }
        throw error
      }
      files[0]?.bytes += data.count
      if record.event.action == .failed {
        let safe = String(decoding: data, as: UTF8.self)
        logger.error("\(safe, privacy: .public)")
      }
    }
  }

  func clear() throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    if FileManager.default.fileExists(atPath: directory.path) {
      try validateDirectory()
    }
    for index in 0..<limits.fileCount {
      if FileManager.default.fileExists(atPath: url(index).path) {
        try FileManager.default.removeItem(at: url(index))
      }
    }
    if FileManager.default.fileExists(atPath: stagingURL.path) {
      try FileManager.default.removeItem(at: stagingURL)
    }
    files.removeAll()
    discardedRecords = 0
    isPrepared = false
  }

  func reportStorageFailure() {
    let message =
      "Local diagnostic storage failed; no diagnostic content was included in this error."
    logger.error("\(message, privacy: .public)")
    fputs("\(message)\n", stderr)
  }

  func url(_ index: Int) -> URL { directory.appendingPathComponent("events-\(index).jsonl") }

  private func validateDirectory() throws {
    var current = directory
    // Foundation caches resource values on URLs, including a failed file-to-directory recovery.
    current.removeAllCachedResourceValues()
    let values = try current.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard values.isDirectory == true, values.isSymbolicLink != true else {
      throw DiagnosticStorageError.invalidFile
    }
  }

  private func inspect(_ index: Int) throws {
    let file = url(index)
    guard FileManager.default.fileExists(atPath: file.path) else { return }
    let values = try file.resourceValues(forKeys: [
      .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
    ])
    guard values.isRegularFile == true, values.isSymbolicLink != true else {
      throw DiagnosticStorageError.invalidFile
    }
    let bytes = values.fileSize ?? 0
    guard bytes > 0, bytes <= limits.fileBytes else {
      try FileManager.default.removeItem(at: file)
      discardedRecords += 1
      return
    }
    let handle = try FileHandle(forUpdating: file)
    do {
      let prefix = try handle.read(upToCount: limits.recordBytes) ?? Data()
      guard let first = prefix.firstIndex(of: 0x0A),
        let record = decode(prefix.prefix(upTo: first)), record.schema == 1
      else {
        try handle.close()
        try FileManager.default.removeItem(at: file)
        discardedRecords += 1
        return
      }
      let tailOffset = max(0, bytes - limits.recordBytes)
      try handle.seek(toOffset: UInt64(tailOffset))
      let tail = try handle.read(upToCount: limits.recordBytes) ?? Data()
      var retainedBytes = bytes
      if tail.last != 0x0A {
        guard let newline = tail.lastIndex(of: 0x0A) else {
          throw DiagnosticStorageError.invalidFile
        }
        retainedBytes = tailOffset + newline + 1
        try handle.truncate(atOffset: UInt64(retainedBytes))
        discardedRecords += 1
      }
      try handle.close()
      files[index] = FileState(bytes: retainedBytes, started: record.timestamp)
    } catch {
      do { try handle.close() } catch { reportStorageFailure() }
      throw error
    }
  }

  private func prune(now: Date) throws {
    let cutoff = now.addingTimeInterval(-limits.retention)
    for (index, state) in files where state.started < cutoff {
      let records = try readRecords(index, after: cutoff)
      guard let first = records.first else {
        try FileManager.default.removeItem(at: url(index))
        files[index] = nil
        continue
      }
      var data = Data()
      let encoder = DiagnosticRecord.encoder()
      for record in records {
        data.append(try encoder.encode(record))
        data.append(0x0A)
      }
      try replace(index, with: data)
      files[index] = FileState(bytes: data.count, started: first.timestamp)
    }
  }

  private var stagingURL: URL { directory.appendingPathComponent("pruning.pending") }

  private func replace(_ index: Int, with data: Data) throws {
    guard data.count <= limits.fileBytes else { throw DiagnosticStorageError.recordTooLarge }
    guard
      FileManager.default.createFile(
        atPath: stagingURL.path, contents: data, attributes: [.posixPermissions: 0o600])
    else { throw DiagnosticStorageError.unavailable }
    _ = try FileManager.default.replaceItemAt(url(index), withItemAt: stagingURL)
  }

  private func rotate() throws {
    let last = limits.fileCount - 1
    if files[last] != nil {
      try FileManager.default.removeItem(at: url(last))
      files[last] = nil
    }
    for source in stride(from: last - 1, through: 0, by: -1) where files[source] != nil {
      try FileManager.default.moveItem(at: url(source), to: url(source + 1))
      files[source + 1] = files.removeValue(forKey: source)
    }
  }

  func decode(_ data: Data) -> DiagnosticRecord? {
    do { return try DiagnosticRecord.decoder().decode(DiagnosticRecord.self, from: data) } catch {
      return nil
    }  // Corrupt records are counted and disclosed by the caller.
  }

  func readRecords(_ index: Int, after cutoff: Date) throws -> [DiagnosticRecord] {
    dispatchPrecondition(condition: .notOnQueue(.main))
    let file = url(index)
    guard FileManager.default.fileExists(atPath: file.path) else { return [] }
    let values = try file.resourceValues(forKeys: [
      .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
    ])
    guard values.isRegularFile == true, values.isSymbolicLink != true,
      let bytes = values.fileSize, bytes <= limits.fileBytes
    else { throw DiagnosticStorageError.invalidFile }
    let handle = try FileHandle(forReadingFrom: file)
    let data: Data
    do {
      data = try handle.read(upToCount: limits.fileBytes) ?? Data()
      try handle.close()
    } catch {
      do { try handle.close() } catch { reportStorageFailure() }
      throw error
    }
    return data.split(separator: 0x0A).compactMap { line in
      guard line.count <= limits.recordBytes, var record = decode(Data(line)), record.schema == 1,
        record.uptime.isFinite, record.uptime >= 0
      else {
        discardedRecords += 1
        return nil
      }
      guard record.timestamp >= cutoff else { return nil }
      record.event = record.event.validated()
      return record
    }
  }
}
