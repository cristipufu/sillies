import Foundation
import Testing

@testable import SilliesApp

@Test @MainActor func trackingScheduleReplacesCallbacksAndStopsAllProducerSlots() {
  let schedule = WindowTrackingSchedule()
  var callbacks: [String] = []
  schedule.once(.settle, after: 0) { callbacks.append("stale") }
  schedule.once(.settle, after: 0) { callbacks.append("replacement") }
  RunLoop.main.run(until: Date().addingTimeInterval(0.01))
  #expect(callbacks == ["replacement"])
  #expect(schedule.pendingCount == 0)
  schedule.once(.discovery(0), after: 0) { callbacks.append("discovery") }
  schedule.repeating(.heartbeat, cadence: .init(interval: 0.001, tolerance: 0)) {
    callbacks.append("heartbeat")
  }
  schedule.once(.transition, after: 0) { callbacks.append("transition") }
  schedule.stop()
  RunLoop.main.run(until: Date().addingTimeInterval(0.01))
  #expect(callbacks == ["replacement"])
  #expect(schedule.pendingCount == 0)
}

@Test @MainActor func trackingScheduleCancelsDiscoveriesWithoutCancellingSettlement() {
  let schedule = WindowTrackingSchedule()
  var settled = false
  for index in 0..<5 {
    schedule.once(.discovery(index), after: 0) { Issue.record("Cancelled discovery ran.") }
  }
  schedule.once(.settle, after: 0) { settled = true }
  schedule.cancelDiscoveries()
  #expect(schedule.pendingCount == 1)
  RunLoop.main.run(until: Date().addingTimeInterval(0.01))
  #expect(settled)
  #expect(schedule.pendingCount == 0)
}
