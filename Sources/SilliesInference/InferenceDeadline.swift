import Foundation

/// One operation budget spans every frame and acknowledgement, including consumer backpressure.
package struct InferenceDeadline: Sendable {
  private let end: ContinuousClock.Instant
  package init(timeout: TimeInterval) { end = .now.advanced(by: .seconds(timeout)) }
  package func remaining() throws -> TimeInterval {
    let remaining = ContinuousClock.now.duration(to: end)
    guard remaining > .zero else { throw InferenceWorkerError.timedOut }
    let value = remaining.components
    return Double(value.seconds) + Double(value.attoseconds) / 1e18
  }
}
