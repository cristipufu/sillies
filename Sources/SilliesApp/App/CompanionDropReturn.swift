import AppKit
import SilliesCore

/// Coordinates a short fall or an exit/entry pair using the existing shared motion clock.
@MainActor
final class CompanionDropReturn {
  private(set) var isActive = false
  private var generation = 0
  private var onArrival: (() -> Void)?
  private var destination: CGPoint?

  func begin(
    for pet: CompanionInstance, plan: DropReturnPlan, reducedMotion: Bool,
    onArrival: @escaping () -> Void
  ) {
    cancel()
    isActive = true
    self.onArrival = onArrival
    destination = plan.destination
    pet.tween = nil
    pet.isStrolling = false
    pet.strollReachesEdge = false
    pet.hud.hide()
    if reducedMotion {
      pet.place(at: plan.destination)
      finish(for: pet, reducedMotion: true)
      return
    }
    switch plan.style {
    case .fall:
      pet.place(at: pet.position)
      pet.tween = MotionTween(
        from: pet.position, to: plan.destination,
        at: ProcessInfo.processInfo.systemUptime, duration: plan.duration, curve: .accelerating)
    case .relocate:
      let token = generation
      pet.presentation.hideForRelocation { [weak self, weak pet] in
        guard let self, let pet, self.generation == token, self.isActive else { return }
        pet.place(at: plan.destination)
        self.finish(for: pet, reducedMotion: false)
      }
    }
  }

  func finish(for pet: CompanionInstance, reducedMotion: Bool) {
    guard isActive else { return }
    let arrival = onArrival
    let target = destination ?? pet.position
    cancel()
    pet.tween = nil
    pet.place(at: target)
    pet.presentation.show(reducedMotion: reducedMotion)
    arrival?()
    pet.refreshHUD()
  }

  func cancel() {
    generation += 1
    isActive = false
    onArrival = nil
    destination = nil
  }
}
