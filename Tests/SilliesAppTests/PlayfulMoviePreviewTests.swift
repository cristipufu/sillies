import AppKit
import SilliesCore
import Testing

@testable import SilliesApp

/// Records Sillies-owned layers only. This opt-in preview never captures the user's desktop.
@Test @MainActor func playfulAnimatedPreviewFrames() throws {
  guard let requested = ProcessInfo.processInfo.environment["SILLIES_PLAYFUL_MOVIES"] else {
    return
  }
  let ids = Set(requested.split(separator: ",").map(String.init))
  let fixture = try PlayfulSceneFixture()
  defer { fixture.stop() }
  let recordingFPS = 30
  for scene in fixture.catalog.scenes where ids.contains(scene.id) {
    let canvas =
      scene.layout == .exterior
      ? CGRect(
        x: fixture.window.minX - 24, y: fixture.window.maxY - 220,
        width: fixture.window.width + 200, height: 460)
      : CGRect(
        x: fixture.visible.minX, y: fixture.window.maxY - 75, width: fixture.visible.width,
        height: max(245, PlayfulPropLayout.requiredHeadroom(for: scene, size: 64) + 75))
    try fixture.start(scene.id)
    try DisplayFrameSequence.presentCreatedWindows()
    let clock = PlayfulPreviewClock()
    let session = PlayfulSceneSession(plan: try fixture.plan(scene.id), at: 0)
    var captureError: (any Error)?
    var frameNumber = 0
    try DisplayFrameSequence.run(count: Int(scene.duration * Double(recordingFPS))) { index in
      let time = Double(index) / Double(recordingFPS)
      fixture.coordinator.advance(at: time)
      guard captureError == nil else { return }
      if let phase = session.phaseIndex(at: time) {
        fixture.sampleAnimations(at: time - session.phaseStart(phase), phase: phase, clock: clock)
      }
      do {
        let name = String(format: "movies/%@/frame-%04d", scene.id, frameNumber)
        try fixture.snapshot(named: name, canvas: canvas, caption: scene.title)
        frameNumber += 1
      } catch { captureError = error }
    }
    if let captureError { throw captureError }
    #expect(frameNumber > 0)
    print("PLAYFUL MOVIE: \(scene.id), \(frameNumber) frames at \(recordingFPS) fps")
  }
}
