import Foundation

/// Backpressure is part of the contract. Only user-facing text reaches this sink, never tool JSON.
package typealias TextDeltaSink = @Sendable (String) async throws -> Void

/// Apple delivers cumulative snapshots. A revision must never silently replay already spoken text.
package struct TextStreamSnapshot: Sendable {
  private var bytes: [UInt8] = []
  package init() {}
  package mutating func append(_ snapshot: String) throws -> String {
    guard snapshot.utf8.count <= TextInferenceWire.maximumMessageBytes / 2 else {
      throw TextModelError.invalidResponse
    }
    let next = Array(snapshot.utf8)
    guard next.starts(with: bytes)
    else { throw TextModelError.invalidResponse }
    let delta = String(decoding: next.dropFirst(bytes.count), as: UTF8.self)
    bytes = next
    return delta
  }
}

/// Coalesces native tokens without a producer timer. Finalization explicitly drains the tail.
package struct TextStreamBatch: Sendable {
  private static let maximumBytes = 128
  private static let interval: Duration = .milliseconds(40)
  private var pending = ""
  private var lastEmission = ContinuousClock.now
  package init() {}
  package mutating func append(_ text: String) -> String? {
    pending += text
    guard
      pending.utf8.count >= Self.maximumBytes
        || lastEmission.duration(to: .now) >= Self.interval
    else { return nil }
    return flush()
  }
  package mutating func flush() -> String? {
    guard !pending.isEmpty else { return nil }
    let result = pending
    pending = ""
    lastEmission = .now
    return result
  }
}
