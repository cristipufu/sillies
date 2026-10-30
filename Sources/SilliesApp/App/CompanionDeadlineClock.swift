import Foundation

/// One cancellable decision deadline for the crew. Behavior selects the deadline; this owns the timer.
@MainActor
final class CompanionDeadlineClock {
  private static let minimumInterval: TimeInterval = 0.08
  private var timer: Timer?
  var onDeadline: (() -> Void)?
  var isScheduled: Bool { timer != nil }

  func schedule(at deadline: TimeInterval) {
    cancel()
    let interval = max(Self.minimumInterval, deadline - ProcessInfo.processInfo.systemUptime)
    let created = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.timer = nil
        self.onDeadline?()
      }
    }
    created.tolerance = Self.minimumInterval
    RunLoop.main.add(created, forMode: .common)
    timer = created
  }

  func cancel() {
    timer?.invalidate()
    timer = nil
  }
}
