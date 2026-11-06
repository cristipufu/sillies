import Foundation

struct DiagnosticRecord: Codable, Sendable {
  let schema: Int
  let launch: UUID
  let sequence: UInt64
  let timestamp: Date
  let uptime: TimeInterval
  var event: DiagnosticEvent

  init(event: DiagnosticEvent, launch: UUID, sequence: UInt64, now: Date = .now) {
    schema = 1
    self.launch = launch
    self.sequence = sequence
    timestamp = now
    uptime = ProcessInfo.processInfo.systemUptime
    self.event = event.validated()
  }

  static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return encoder
  }

  static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
