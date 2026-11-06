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
    let response: CFArray?
    switch request {
    case .windowList(let options, let reference):
      response = CGWindowListCopyWindowInfo(CGWindowListOption(rawValue: options), reference)
    case .windows(let ids):
      response = try describe(ids)
    }
    guard let entries = response as? [[String: Any]]
    else { throw WindowMetadataError.snapshotUnavailable }
    return WindowMetadataSnapshot(entries: entries, capturedAt: capturedAt)
  }

  private static func describe(_ ids: [UInt32]) throws -> CFArray? {
    guard !ids.isEmpty, ids.count <= WindowMetadataRequest.maximumTargetWindows,
      ids.allSatisfy({ $0 != kCGNullWindowID }), Set(ids).count == ids.count
    else { throw POSIXError(.EINVAL) }
    // Quartz expects pointer-sized raw CGWindowID values, not CFNumber objects.
    var values = ids.map { UnsafeRawPointer(bitPattern: UInt($0)) }
    return values.withUnsafeMutableBufferPointer { buffer in
      guard let array = CFArrayCreate(nil, buffer.baseAddress, buffer.count, nil) else {
        return nil
      }
      return CGWindowListCreateDescriptionFromArray(array)
    }
  }
}
