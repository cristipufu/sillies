import Foundation

package struct DiagnosticLimits: Sendable {
  package static let standard = DiagnosticLimits()
  package var fileBytes = 2_000_000
  // Four files retain at most 8 MB; one bounded atomic-pruning file keeps peak storage <= 10 MB.
  package var fileCount = 4
  package var retention: TimeInterval = 7 * 24 * 60 * 60
  package var pendingEvents = 256
  package var recordBytes = 2_048
  package var exportBytes = 10_000_000
  static let exportMetadataReserve = 4_096

  func validate() throws {
    guard fileBytes >= recordBytes, fileBytes <= Self.standard.fileBytes,
      (1...Self.standard.fileCount).contains(fileCount),
      retention.isFinite, retention > 0, retention <= Self.standard.retention,
      (1...Self.standard.pendingEvents).contains(pendingEvents),
      (256...Self.standard.recordBytes).contains(recordBytes),
      exportBytes > Self.exportMetadataReserve, exportBytes <= Self.standard.exportBytes
    else { throw DiagnosticStorageError.invalidLimits }
  }
}

package enum DiagnosticStorageError: Error {
  case invalidLimits, unavailable, invalidFile, recordTooLarge
}
