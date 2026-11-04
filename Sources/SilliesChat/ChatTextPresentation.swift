/// One in-flight UI update and one replaceable snapshot. Generation never waits for a renderer.
actor ChatTextPresentation {
  private let receive: @Sendable (String) async -> Void
  private var pending: String?
  private var worker: Task<Void, Never>?
  private var closed = false

  init(receive: @escaping @Sendable (String) async -> Void) { self.receive = receive }

  func submit(_ text: String) {
    guard !closed else { return }
    pending = text
    if worker == nil { worker = Task { await drain() } }
  }

  /// The final snapshot must reach presentation before the turn owner commits its result.
  func finish() async {
    closed = true
    await worker?.value
  }

  private func drain() async {
    while let text = pending {
      pending = nil
      await receive(text)
    }
    worker = nil
  }
}
