import Testing

@testable import SilliesCore

@Test func audioLifecycleEventSequencesPreserveActiveDurationAndNeverRestartFinishedSessions() {
  // Exhaust all six-command sequences of pause/resume/repeated-start/late-start callbacks.
  for sequence in 0..<4_096 {
    var lifecycle = AudioSessionLifecycle()
    lifecycle.beginPreparation()
    lifecycle.beginCapture(at: 100)
    var expectedDuration = 0.0
    var active = true
    var encoded = sequence
    for offset in 1...6 {
      if active { expectedDuration += 1 }
      let now = 100 + Double(offset)
      switch encoded % 4 {
      case 0:
        lifecycle.pause(at: now)
        active = false
      case 1:
        lifecycle.resume(at: now)
        active = true
      case 2: lifecycle.beginPreparation()
      default: lifecycle.beginCapture(at: now)
      }
      encoded /= 4
      #expect(lifecycle.elapsed(at: now) == expectedDuration)
    }
    lifecycle.beginFinishing(at: 106)
    lifecycle.completeFinishing()
    lifecycle.resume(at: 200)
    lifecycle.beginCapture(at: 200)
    lifecycle.beginPreparation()
    lifecycle.fail(.init(category: .captureInterrupted, message: "Late device error"), at: 200)
    #expect(lifecycle.phase == .finished)
    #expect(lifecycle.elapsed(at: 200) == expectedDuration)
    #expect(lifecycle.failure == nil)
  }
}

@Test func audioLifecycleFailureFreezesPausedDurationAndPreservesTheOriginalError() {
  var lifecycle = AudioSessionLifecycle()
  lifecycle.beginPreparation()
  lifecycle.beginCapture(at: 0)
  lifecycle.pause(at: 10)
  lifecycle.fail(.init(category: .captureInterrupted, message: "Microphone disconnected"), at: 50)
  lifecycle.resume(at: 60)
  lifecycle.beginCapture(at: 70)
  #expect(lifecycle.elapsed(at: 80) == 10)
  lifecycle.beginFinishing(at: 100)
  lifecycle.recordFinalizationNotice(
    .init(category: .finalization, message: "Recognizer timed out"))
  #expect(lifecycle.failure?.message == "Microphone disconnected")
  lifecycle.recordRecordingFailure(.init(category: .recordingSave, message: "Disk full"))
  lifecycle.completeFinishing()
  #expect(lifecycle.failure?.message == "Disk full")
  #expect(lifecycle.elapsed(at: 200) == 10)
}

@Test func audioLifecycleFinishIsIdempotentBeforeStartAndDuringPreparation() {
  for prepare in [false, true] {
    var lifecycle = AudioSessionLifecycle()
    if prepare { lifecycle.beginPreparation() }
    let firstFinish = lifecycle.beginFinishing(at: 100)
    let secondFinish = lifecycle.beginFinishing(at: 200)
    let lateCapture = lifecycle.beginCapture(at: 300)
    let firstCompletion = lifecycle.completeFinishing()
    let secondCompletion = lifecycle.completeFinishing()
    #expect(firstFinish)
    #expect(!secondFinish)
    #expect(!lateCapture)
    #expect(firstCompletion)
    #expect(!secondCompletion)
    #expect(lifecycle.elapsed(at: 400) == 0)
  }
}
