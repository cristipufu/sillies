import SilliesCore
import Testing

@Test func tinyAudioCallbacksDoNotExhaustTheCaptureBudgetPrematurely() {
  var budget = AudioInputBudget<String>()
  for _ in 0..<3_000 {
    #expect(budget.reserve(duration: 0.001, source: "Meeting") == .accepted)
  }
  for _ in 0..<3_000 { budget.release(duration: 0.001, source: "Meeting") }
  #expect(budget.reserve(duration: 10, source: "Meeting") == .accepted)
  #expect(budget.reserve(duration: 3, source: "Meeting") == .full)
  #expect(budget.reserve(duration: 10, source: "Microphone") == .accepted)
}

@Test func audioAdmissionRejectsInvalidDurationsWithoutConsumingCapacity() {
  var budget = AudioInputBudget<String>()
  for duration in [Double.nan, .infinity, 0, -1] {
    #expect(budget.reserve(duration: duration, source: "Meeting") == .invalid)
  }
  #expect(budget.reserve(duration: 12, source: "Meeting") == .accepted)
  #expect(budget.reserve(duration: 0.1, source: "Meeting") == .full)
}
