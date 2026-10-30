import Foundation

/// The only bridge for non-Sendable worker state. Access is synchronous on its owning queue,
/// never a blocking dispatch. The value is private, and results must be Sendable.
final class SerialQueueStorage<Value: AnyObject>: @unchecked Sendable {
  private let queue: DispatchQueue
  private let value: Value

  init(queue: DispatchQueue, makeValue: () -> Value) {
    self.queue = queue
    value = makeValue()
  }

  func withValue<Result: Sendable>(_ operation: (Value) throws -> Result) rethrows -> Result {
    dispatchPrecondition(condition: .onQueue(queue))
    return try operation(value)
  }
}
