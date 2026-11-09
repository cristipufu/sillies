import SilliesCore
import Testing

@Test(arguments: [
  SessionFailure.Category.captureInterrupted, .captureUnavailable, .permissionDenied,
  .audioProcessing, .transcription, .recordingSave, .finalization, .unknown,
])
func verifiedWindowClosureOnlyExplainsCaptureInterruption(_ category: SessionFailure.Category) {
  let failure = SessionFailure(category: category, message: "Fixture")
  #expect(failure.requiresAttention(ending: .userFinished))
  #expect(failure.requiresAttention(ending: .sourceClosed) == (category != .captureInterrupted))
}

@Test func verifiedClosureAllowsLaterSaveAndFinalizationFailuresToSurface() {
  for category in [SessionFailure.Category.finalization, .recordingSave] {
    var lifecycle = AudioSessionLifecycle()
    lifecycle.beginPreparation()
    lifecycle.beginCapture(at: 1)
    lifecycle.fail(.init(category: .captureInterrupted, message: "Stream ended"), at: 2)
    lifecycle.beginFinishing(at: 3, reason: .sourceClosed)
    let failure = SessionFailure(category: category, message: "Fixture failure")
    if category == .recordingSave {
      lifecycle.recordRecordingFailure(failure)
    } else {
      lifecycle.recordFinalizationNotice(failure)
    }
    #expect(lifecycle.failure == failure)
    #expect(lifecycle.elapsed(at: 4) == 1)
  }
}
