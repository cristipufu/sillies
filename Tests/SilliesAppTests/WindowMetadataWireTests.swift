import Foundation
import Testing
import WindowMetadataProtocol

@Test
func metadataResponseRejectsOversizedOrIncompleteHeadersBeforeAllocating() {
  let oversized = Data(repeating: .max, count: WindowMetadataWire.responseHeaderBytes)
  #expect(throws: WindowMetadataError.responseTooLarge) {
    try WindowMetadataWire.responseLength(from: oversized)
  }
  #expect(throws: WindowMetadataError.invalidResponse) {
    try WindowMetadataWire.responseLength(from: Data([0, 1]))
  }
}

@Test
func metadataSnapshotPreservesCaptureTimeAndDistinguishesEmptyFromMalformed() throws {
  let snapshot = WindowMetadataSnapshot(entries: [], capturedAt: 125.75)
  let payload = try WindowMetadataWire.encode(snapshot)
  let length = try WindowMetadataWire.responseLength(from: WindowMetadataWire.header(for: payload))
  #expect(length == payload.count)
  let decoded = try WindowMetadataWire.decode(payload)
  #expect(decoded.entries.isEmpty)
  #expect(decoded.capturedAt == snapshot.capturedAt)
  let missingCaptureTime = try PropertyListSerialization.data(
    fromPropertyList: ["windows": []], format: .binary, options: 0)
  #expect(throws: WindowMetadataError.invalidResponse) {
    try WindowMetadataWire.decode(missingCaptureTime)
  }
}
