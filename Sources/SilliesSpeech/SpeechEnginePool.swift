import Foundation

package protocol ReusableSpeechEngine: SpeechWindowEngine {
  func resetForReuse() async throws
}

/// Only idle, reset engines are retained. Every channel receives an exclusive lease.
package actor SpeechEnginePool<Key: Hashable & Sendable> {
  private struct Idle {
    let key: Key
    let engine: any ReusableSpeechEngine
  }
  private static var maximumIdleEngines: Int { 2 }
  private let make: @Sendable (Key) async throws -> any ReusableSpeechEngine
  private var idle: [Idle] = []

  package init(
    prepared: (key: Key, engine: any ReusableSpeechEngine),
    make: @escaping @Sendable (Key) async throws -> any ReusableSpeechEngine
  ) {
    idle = [Idle(key: prepared.key, engine: prepared.engine)]
    self.make = make
  }

  package func acquire(for key: Key) async throws -> SpeechEngineLease {
    try Task.checkCancellation()
    let engine: any ReusableSpeechEngine
    if let index = idle.lastIndex(where: { $0.key == key }) {
      engine = idle.remove(at: index).engine
    } else {
      engine = try await make(key)
    }
    try Task.checkCancellation()
    return SpeechEngineLease(engine: engine) { [weak self] engine in
      await self?.recycle(engine, for: key)
    }
  }

  private func recycle(_ engine: any ReusableSpeechEngine, for key: Key) {
    idle.append(Idle(key: key, engine: engine))
    if idle.count > Self.maximumIdleEngines { idle.removeFirst() }
  }
}
