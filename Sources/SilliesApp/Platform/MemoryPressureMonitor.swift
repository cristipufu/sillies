import Foundation

/// Owns the native subscription; consumers decide which resources to release.
actor MemoryPressureMonitor {
  enum Pressure: Sendable { case normal, constrained }
  private var source: (any DispatchSourceMemoryPressure)?
  private var generation: UUID?

  func start(receive: @escaping @Sendable (Pressure) async -> Void) {
    guard source == nil else { return }
    let id = UUID()
    let source = DispatchSource.makeMemoryPressureSource(
      eventMask: [.normal, .warning, .critical], queue: .global(qos: .utility))
    source.setEventHandler { [weak self] in
      Task { await self?.report(id: id, receive: receive) }
    }
    self.source = source
    generation = id
    source.resume()
  }

  func stop() {
    generation = nil
    source?.cancel()
    source = nil
  }

  private func report(id: UUID, receive: @Sendable (Pressure) async -> Void) async {
    guard generation == id, let event = source?.data else { return }
    await receive(event.contains(.warning) || event.contains(.critical) ? .constrained : .normal)
  }
}
