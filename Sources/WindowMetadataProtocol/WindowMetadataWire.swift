import Foundation

public enum WindowMetadataWire {
  public static let maximumResponseBytes = 8 * 1024 * 1024
  public static let responseHeaderBytes = MemoryLayout<UInt32>.size
  public static let requestTerminator: UInt8 = 0x0A
  private static let entriesKey = "windows"
  private static let captureTimeKey = "capturedAt"

  public static func encode(_ snapshot: WindowMetadataSnapshot) throws -> Data {
    let payload = try PropertyListSerialization.data(
      fromPropertyList: [entriesKey: snapshot.entries, captureTimeKey: snapshot.capturedAt],
      format: .binary, options: 0)
    guard payload.count <= maximumResponseBytes else { throw WindowMetadataError.responseTooLarge }
    return payload
  }

  public static func decode(_ payload: Data) throws -> WindowMetadataSnapshot {
    guard
      let reply = try PropertyListSerialization.propertyList(from: payload, format: nil)
        as? [String: Any],
      let entries = reply[entriesKey] as? [[String: Any]],
      let capturedAt = reply[captureTimeKey] as? TimeInterval, capturedAt.isFinite
    else { throw WindowMetadataError.invalidResponse }
    return WindowMetadataSnapshot(entries: entries, capturedAt: capturedAt)
  }

  public static func header(for payload: Data) -> Data {
    var length = UInt32(payload.count).bigEndian
    return withUnsafeBytes(of: &length) { Data($0) }
  }

  public static func responseLength(from header: Data) throws -> Int {
    guard header.count == responseHeaderBytes else { throw WindowMetadataError.invalidResponse }
    let length = header.withUnsafeBytes { UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self)) }
    guard length <= maximumResponseBytes else { throw WindowMetadataError.responseTooLarge }
    return Int(length)
  }
}
