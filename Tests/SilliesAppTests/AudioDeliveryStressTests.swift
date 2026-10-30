import Foundation
import SilliesAudio
import Synchronization
import Testing

@testable import SilliesApp

@Test @MainActor func blockedUIKeepsOnlyLatestProgressAndOneScheduledDelivery() {
  let scheduler = ManualAudioDelivery()
  var delivered: [AudioCaptureUpdate] = []
  let delivery = AudioSessionUpdateDelivery(schedule: scheduler.schedule) {
    delivered.append($0)
  }
  let clock = ContinuousClock()
  let started = clock.now
  let updateCount = 100_000
  for index in 0..<updateCount {
    delivery.enqueue(.transcript("Progress \(index)", level: 0.5, elapsed: Double(index)))
  }
  #expect(scheduler.pendingCount == 1)
  #expect(delivery.metrics.pendingUpdates == 1)
  #expect(delivery.metrics.peakPendingUpdates == 1)
  #expect(delivery.metrics.scheduledDeliveries == 1)
  scheduler.drain()
  #expect(delivered.count == 1)
  if case .transcript(let text, _, let elapsed) = delivered.first {
    #expect(text == "Progress 99999")
    #expect(elapsed == 99_999)
  } else {
    Issue.record("Expected the most recent transcript.")
  }
  #expect(delivery.metrics.pendingUpdates == 0)
  print(
    "AUDIO DELIVERY STRESS: \(updateCount) updates in \(clock.now - started); peak pending 1, scheduled deliveries 1."
  )
}

@Test @MainActor func progressCoalescingPreservesLifecycleOrderingAndStopDuringDelivery() {
  let scheduler = ManualAudioDelivery()
  var received: [String] = []
  var delivery: AudioSessionUpdateDelivery?
  delivery = AudioSessionUpdateDelivery(schedule: scheduler.schedule) { update in
    switch update {
    case .capturing: received.append("capturing")
    case .transcript(let text, _, _): received.append(text)
    case .failed:
      received.append("failed")
      delivery?.stop()
    default: Issue.record("Unexpected lifecycle event.")
    }
  }
  delivery?.enqueue(.capturing("Meeting"))
  delivery?.enqueue(.transcript("old", level: 0, elapsed: 1))
  delivery?.enqueue(.transcript("latest", level: 0, elapsed: 2))
  delivery?.enqueue(.failed(.init(category: .captureInterrupted, message: "Capture ended")))
  delivery?.enqueue(.transcript("late", level: 0, elapsed: 3))
  scheduler.drain()
  #expect(received == ["capturing", "latest", "failed"])
  delivery?.enqueue(.transcript("after stop", level: 0, elapsed: 4))
  #expect(scheduler.pendingCount == 0)
  delivery = nil
}

@Test @MainActor func cancelledDeliveryReleasesSessionWithoutDrainingTheMainRunLoop() {
  let scheduler = ManualAudioDelivery()
  for _ in 0..<100 {
    var delivery: AudioSessionUpdateDelivery? = AudioSessionUpdateDelivery(
      schedule: scheduler.schedule
    ) { _ in
      Issue.record("Stopped sessions must not publish.")
    }
    weak var released = delivery
    delivery?.enqueue(.transcript(String(repeating: "x", count: 8_192), level: 0, elapsed: 1))
    delivery?.stop()
    #expect(delivery?.metrics.pendingUpdates == 0)
    delivery = nil
    #expect(released == nil)
  }
  scheduler.drain()
  #expect(scheduler.pendingCount == 0)
}

private final class ManualAudioDelivery: Sendable {
  private let actions = Mutex<[@MainActor @Sendable () -> Void]>([])
  var pendingCount: Int { actions.withLock { $0.count } }
  func schedule(_ action: @escaping @MainActor @Sendable () -> Void) {
    actions.withLock { $0.append(action) }
  }
  @MainActor func drain() {
    let pending = actions.withLock { actions in
      let pending = actions
      actions.removeAll()
      return pending
    }
    for action in pending { action() }
  }
}
