import Testing

@testable import SilliesCore

@Test func feedbackRetargetingContinuesFromTheCurrentPose() {
  let rest = WindowMotionFeedback(lean: 0, stretch: 0)
  let target = WindowMotionFeedback(lean: 0.2, stretch: 0.1)
  let motion = WindowFeedbackAnimation(from: rest, to: target, at: 10, style: .following)
  let interruptedAt = 10 + WindowFeedbackAnimation.followDuration / 3
  let presented = motion.value(at: interruptedAt)
  #expect(abs(presented.lean - target.lean / 3) < 0.00001)
  #expect(abs(presented.stretch - target.stretch / 3) < 0.00001)

  let reversed = WindowFeedbackAnimation(
    from: presented, to: rest, at: interruptedAt, style: .following)
  #expect(reversed.value(at: interruptedAt) == presented)
  #expect(reversed.value(at: interruptedAt + reversed.duration + 1) == rest)
  #expect(reversed.value(at: interruptedAt - 1) == presented)
}

@Test func settlingCanBeInterruptedWithoutJumpingToTheRestPose() {
  let leaning = WindowMotionFeedback(lean: 0.2, stretch: 0.1)
  let rest = WindowMotionFeedback(lean: 0, stretch: 0)
  let settling = WindowFeedbackAnimation(from: leaning, to: rest, at: 0, style: .settling)
  #expect(settling.value(at: 0) == leaning)
  let presented = settling.value(at: 0.2)
  #expect(presented.lean < 0)
  let resumed = WindowFeedbackAnimation(from: presented, to: leaning, at: 0.2, style: .following)
  #expect(resumed.value(at: 0.2) == presented)
  #expect(settling.value(at: settling.duration) == rest)
}
