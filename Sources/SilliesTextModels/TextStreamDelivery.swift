/// Track externally visible output so preemption cannot replay a prefix on an implicit retry.
actor TextStreamDelivery {
  private let receive: TextDeltaSink
  private(set) var hasOutput = false
  init(receive: @escaping TextDeltaSink) { self.receive = receive }
  func append(_ delta: String) async throws {
    try Task.checkCancellation()
    guard !delta.isEmpty else { return }
    hasOutput = true
    try await receive(delta)
  }
}
