import CoreGraphics
import Foundation
import WindowMetadataProtocol

/// No AppKit, windows, or Core Animation transactions in this process. EOF stops it if its
/// parent exits; the parent also terminates it when the last tracking owner stops.
enum WindowMetadataService {
  static func run() {
    while let line = readLine() {
      do {
        try autoreleasepool { try respond(to: line) }
      } catch {
        fputs("Window metadata helper failed: \(error.localizedDescription)\n", stderr)
        exit(EXIT_FAILURE)
      }
    }
  }

  private static func respond(to line: String) throws {
    let request = try JSONDecoder().decode(WindowMetadataRequest.self, from: Data(line.utf8))
    let payload = try WindowMetadataWire.encode(capture(request))
    try FileHandle.standardOutput.write(contentsOf: WindowMetadataWire.header(for: payload))
    try FileHandle.standardOutput.write(contentsOf: payload)
  }

  private static func capture(_ request: WindowMetadataRequest) throws -> WindowMetadataSnapshot {
    let capturedAt = ProcessInfo.processInfo.systemUptime
    guard
      let entries = CGWindowListCopyWindowInfo(
        CGWindowListOption(rawValue: request.options), request.reference) as? [[String: Any]]
    else { throw WindowMetadataError.snapshotUnavailable }
    return WindowMetadataSnapshot(entries: entries, capturedAt: capturedAt)
  }
}
