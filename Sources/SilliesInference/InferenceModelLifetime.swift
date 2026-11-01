import Foundation

/// Explicit consumer lifetime; registries retain idle models without preventing pressure eviction.
package actor InferenceModelLifetime {
  package nonisolated let id = UUID()
  package private(set) var isActive = true
  private var endings: [UUID: @Sendable () async -> Void] = [:]
  package init() {}
  package func onEnd(owner: UUID, perform: @escaping @Sendable () async -> Void) async {
    guard isActive else {
      await perform()
      return
    }
    endings[owner] = perform
  }
  package func end() async {
    guard isActive else { return }
    isActive = false
    let callbacks = Array(endings.values)
    endings.removeAll()
    for callback in callbacks { await callback() }
  }
}
