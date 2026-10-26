import CoreGraphics
import Testing

@testable import SilliesCore

private let initialWindow = CGRect(x: 100, y: 200, width: 700, height: 500)
private let titlePointer = CGPoint(x: 350, y: 680)

@Test func toolbarContentDragNeverInventsWindowMovement() throws {
  let gesture = try #require(
    PointerWindowGesture(frame: initialWindow, pointer: titlePointer, at: 0))
  var session = WindowDragSession(gesture: gesture)
  for step in 1...100 {
    let time = Double(step) / 120
    let point = CGPoint(x: titlePointer.x + Double(step), y: titlePointer.y)
    session.record(pointer: point, at: time)
    #expect(session.observe(initialWindow, capturedAt: time, now: time) == .useMetadata)
    #expect(session.predictedFrame(at: point) == nil)
  }
  #expect(session.mode == .pending)
}

@Test func actualMovementEnablesImmediatePointerAttachment() throws {
  let gesture = try #require(
    PointerWindowGesture(frame: initialWindow, pointer: titlePointer, at: 0))
  var session = WindowDragSession(gesture: gesture)
  let first = CGPoint(x: 360, y: 680)
  session.record(pointer: first, at: 0.01)
  #expect(
    session.observe(initialWindow.offsetBy(dx: 10, dy: 0), capturedAt: 0.01, now: 0.02)
      == .usePointer)
  #expect(
    session.predictedFrame(at: CGPoint(x: 500, y: 710)) == initialWindow.offsetBy(dx: 150, dy: 30))
}

@Test func repeatedSamplesKeepTimeBasedHistoryForDelayedMetadata() throws {
  let gesture = try #require(
    PointerWindowGesture(frame: initialWindow, pointer: titlePointer, at: 0))
  var session = WindowDragSession(gesture: gesture)
  for index in 1...240 {
    session.record(pointer: CGPoint(x: 350 + Double(index), y: 680), at: Double(index) / 480)
  }
  #expect(
    session.observe(initialWindow.offsetBy(dx: 10, dy: 0), capturedAt: 0.01, now: 0.5)
      == .usePointer)
  #expect(session.mode == .pointer)
}

@Test func constrainedDragFallsBackWithoutEndingTheLiveSession() throws {
  let gesture = try #require(
    PointerWindowGesture(frame: initialWindow, pointer: titlePointer, at: 0))
  var session = WindowDragSession(gesture: gesture)
  session.record(pointer: CGPoint(x: 360, y: 680), at: 0.01)
  _ = session.observe(initialWindow.offsetBy(dx: 10, dy: 0), capturedAt: 0.01, now: 0.01)
  let snapped = CGRect(x: 0, y: 0, width: 1400, height: 900)
  #expect(session.observe(snapped, capturedAt: 0.3, now: 0.3) == .ignore)
  #expect(session.observe(snapped, capturedAt: 0.5, now: 0.5) == .useMetadata)
  #expect(session.mode == .metadata)
  #expect(session.predictedFrame(at: titlePointer) == nil)
}

@Test func firstPixelOfBottomResizeDoesNotBecomeAWindowMove() throws {
  let origin = CGPoint(x: initialWindow.maxX, y: initialWindow.minY)
  let gesture = try #require(PointerWindowGesture(frame: initialWindow, pointer: origin, at: 0))
  var session = WindowDragSession(gesture: gesture)
  let first = CGPoint(x: origin.x, y: origin.y - 1)
  session.record(pointer: first, at: 0.01)
  _ = session.observe(gesture.frame(at: first), capturedAt: 0.01, now: 0.01)
  #expect(session.gesture.kind == gesture.kind)
  #expect(session.predictedFrame(at: CGPoint(x: origin.x, y: origin.y - 80))?.height == 580)
}

@Test func unifiedToolbarHeaderDepthSupportsPointerGestureAndReanchorsAfterDragThreshold() throws {
  let deepHeaderPointer = CGPoint(x: 350, y: initialWindow.maxY - 56)
  let gesture = try #require(
    PointerWindowGesture(frame: initialWindow, pointer: deepHeaderPointer, at: 0))
  #expect(gesture.kind == .move)
  var session = WindowDragSession(gesture: gesture)
  // Simulate a custom toolbar with a 12pt drag threshold before the window starts moving.
  let thresholdPointer = CGPoint(x: deepHeaderPointer.x + 25, y: deepHeaderPointer.y)
  let firstMovedFrame = initialWindow.offsetBy(dx: 13, dy: 0)
  session.record(pointer: thresholdPointer, at: 0.016)
  #expect(session.observe(firstMovedFrame, capturedAt: 0.016, now: 0.016) == .useMetadata)
  let nextPointer = CGPoint(x: thresholdPointer.x + 15, y: thresholdPointer.y)
  session.record(pointer: nextPointer, at: 0.024)
  #expect(
    session.observe(firstMovedFrame.offsetBy(dx: 15, dy: 0), capturedAt: 0.024, now: 0.024)
      == .usePointer)
  #expect(session.mode == .pointer)

  // Simulate dense 120Hz pointer samples during a 14pt drag threshold followed by dispatch delay:
  // the first 2pt window movement at t=8/120 must compare against samples near capturedAt (not
  // ancient pre-threshold samples) and reanchor cleanly before entering pointer mode.
  var denseSession = WindowDragSession(gesture: gesture)
  for step in 1...8 {
    let time = Double(step) / 120
    denseSession.record(
      pointer: CGPoint(x: deepHeaderPointer.x + Double(step * 2), y: deepHeaderPointer.y),
      at: time)
  }
  let earlyConfirmTime = 8.0 / 120
  #expect(
    denseSession.observe(
      initialWindow.offsetBy(dx: 2, dy: 0), capturedAt: earlyConfirmTime, now: earlyConfirmTime)
      == .useMetadata)
  let laterCaptureTime = 0.40
  let laterPointer = CGPoint(x: deepHeaderPointer.x + 114, y: deepHeaderPointer.y)
  denseSession.record(pointer: laterPointer, at: laterCaptureTime)
  denseSession.record(
    pointer: CGPoint(x: laterPointer.x + 18, y: laterPointer.y), at: laterCaptureTime + 0.008)
  #expect(
    denseSession.observe(
      initialWindow.offsetBy(dx: 100, dy: 0),
      capturedAt: laterCaptureTime,
      now: laterCaptureTime + 0.008) == .usePointer)
  #expect(denseSession.mode == .pointer)
  #expect(
    denseSession.predictedFrame(at: CGPoint(x: laterPointer.x + 30, y: laterPointer.y))
      == initialWindow.offsetBy(dx: 130, dy: 0))
}

@Test func highVelocityWindowDragInterpolatesSubframeSamplesAndResumesFromConstraint() throws {
  let gesture = try #require(
    PointerWindowGesture(frame: initialWindow, pointer: titlePointer, at: 0))
  var session = WindowDragSession(gesture: gesture)
  // Fast 40pt jump in a single 8ms frame; intermediate 18pt window snapshot must still match.
  let fastPointer = CGPoint(x: titlePointer.x + 40, y: titlePointer.y - 20)
  session.record(pointer: fastPointer, at: 0.008)
  #expect(
    session.observe(initialWindow.offsetBy(dx: 20, dy: -10), capturedAt: 0.004, now: 0.008)
      == .usePointer)
  #expect(session.mode == .pointer)

  // If a constrained window temporarily falls back to metadata, moving freely again resumes pointer mode.
  let constrained = CGRect(x: 120, y: 800, width: 700, height: 500)
  _ = session.observe(constrained, capturedAt: 0.30, now: 0.30)
  #expect(session.observe(constrained, capturedAt: 0.50, now: 0.50) == .useMetadata)
  #expect(session.mode == .metadata)

  let resumePointer = CGPoint(x: fastPointer.x + 30, y: fastPointer.y - 30)
  session.record(pointer: resumePointer, at: 0.508)
  let resumedFrame = constrained.offsetBy(dx: 30, dy: -30)
  #expect(session.observe(resumedFrame, capturedAt: 0.508, now: 0.508) == .usePointer)
  #expect(session.mode == .pointer)
}
