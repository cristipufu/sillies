import Foundation

/// Serializes runtime transitions. Wake waits for teardown; rapid changes retain only the latest intent.
@MainActor final class ModelActivityCoordinator {
  enum Activity: Sendable { case active, suspended }
  private let apply: @MainActor (Activity) async -> Void
  private var desired = Activity.suspended
  private var applied: Activity?
  private var transition: Task<Void, Never>?

  init(apply: @escaping @MainActor (Activity) async -> Void) { self.apply = apply }

  func setActivity(_ activity: Activity) {
    desired = activity
    guard transition == nil, applied != desired else { return }
    transition = Task { [weak self] in await self?.reconcile() }
  }

  func stop() { setActivity(.suspended) }

  private func reconcile() async {
    while applied != desired {
      let target = desired
      await apply(target)
      applied = target
    }
    transition = nil
  }
}
