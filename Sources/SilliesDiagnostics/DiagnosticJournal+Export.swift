import Foundation

extension DiagnosticJournal {
  struct ExportRequest: Sendable {
    let destination: URL
    let environment: DiagnosticEnvironment
    let droppedEvents: Int
    let now: Date
  }

  private struct ExportHeader: Encodable {
    let schema = 1
    let exportedAt: Date
    let environment: DiagnosticEnvironment
    let retainedFileBytes: Int
    let retainedFileCount: Int
    let retentionSeconds: TimeInterval
    let maximumExportBytes: Int
    let droppedEvents: Int
  }

  func export(_ request: ExportRequest) throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    guard
      request.destination.standardizedFileURL.deletingLastPathComponent()
        != directory.standardizedFileURL
    else { throw DiagnosticStorageError.invalidFile }
    try prepare(now: request.now)
    let encoder = DiagnosticRecord.encoder()
    let header = ExportHeader(
      exportedAt: request.now, environment: request.environment,
      retainedFileBytes: limits.fileBytes, retainedFileCount: limits.fileCount,
      retentionSeconds: limits.retention, maximumExportBytes: limits.exportBytes,
      droppedEvents: request.droppedEvents)
    var retained: [Data] = []
    var size = 0
    var skipped = 0
    let recordBudget = limits.exportBytes - DiagnosticLimits.exportMetadataReserve
    let cutoff = request.now.addingTimeInterval(-limits.retention)
    for index in 0..<limits.fileCount {
      for record in try readRecords(index, after: cutoff).reversed() {
        let encoded = try encoder.encode(record)
        guard encoded.count <= limits.recordBytes, size + encoded.count + 1 <= recordBudget else {
          skipped += 1
          continue
        }
        retained.append(encoded)
        size += encoded.count + 1
      }
    }
    var output = Data("{\"metadata\":".utf8)
    output.append(try encoder.encode(header))
    output.append(Data(",\"events\":[".utf8))
    for (index, record) in retained.reversed().enumerated() {
      if index > 0 { output.append(0x2C) }
      output.append(record)
    }
    output.append(
      Data("],\"invalidRecords\":\(discardedRecords),\"omittedForExportLimit\":\(skipped)}\n".utf8))
    guard output.count <= limits.exportBytes else { throw DiagnosticStorageError.recordTooLarge }
    try output.write(to: request.destination, options: .atomic)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600], ofItemAtPath: request.destination.path)
  }
}
