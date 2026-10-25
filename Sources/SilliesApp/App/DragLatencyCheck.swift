import AppKit
import SilliesCore

/// Samples attachment error during every update, rather than waiting for the window to settle.
@MainActor
final class DragLatencyCheck {
  private let controller: CompanionController
  private let playground: WindowPlayground
  private let allowLag: Bool
  private var timer: Timer?
  private var base = CGRect.zero
  private var fractions: [Double] = []
  private var started: Double = 0
  private var moveErrors: [Double] = []
  private var resizeErrors: [Double] = []

  init(controller: CompanionController, playground: WindowPlayground, allowLag: Bool) {
    self.controller = controller
    self.playground = playground
    self.allowLag = allowLag
  }

  func start() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
      base = playground.window.frame
      let visible =
        (playground.window.screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
        ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
      let surface = PerchSurface(
        window: base, visibleFrame: visible, characterSize: controller.settings.size)
      fractions = controller.attachmentDiagnostics.map { surface.fraction(for: $0.point) }
      started = ProcessInfo.processInfo.systemUptime
      let timer = Timer(timeInterval: 1 / 120, repeats: true) { [self] _ in
        MainActor.assumeIsolated { tick() }
      }
      self.timer = timer
      RunLoop.main.add(timer, forMode: .common)
    }
  }

  private func tick() {
    let elapsed = ProcessInfo.processInfo.systemUptime - started
    guard elapsed < 2.5 else {
      finish()
      return
    }
    var frame = base
    if elapsed < 1.25 {
      frame.origin.x += sin(elapsed * 5) * 110
      frame.origin.y += sin(elapsed * 6) * 30
    } else {
      frame.size.width += sin((elapsed - 1.25) * 5) * 100
      frame.size.height += sin((elapsed - 1.25) * 6) * 35
    }
    playground.window.setFrame(frame, display: true)
    let actual = playground.window.frame
    let visible =
      (playground.window.screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
      ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    let surface = PerchSurface(
      window: actual, visibleFrame: visible, characterSize: controller.settings.size)
    for (index, attachment) in controller.attachmentDiagnostics.enumerated() {
      guard fractions.indices.contains(index) else { continue }
      let expected = surface.point(at: fractions[index])
      let error = hypot(expected.x - attachment.point.x, expected.y - attachment.point.y)
      if elapsed < 1.25 { moveErrors.append(error) } else { resizeErrors.append(error) }
    }
  }

  private func finish() {
    timer?.invalidate()
    timer = nil
    let move = moveErrors.max() ?? .infinity
    let resize = resizeErrors.max() ?? .infinity
    print(
      String(
        format:
          "DRAG LATENCY: move max %.2f pt, resize max %.2f pt; %d live attachment samples at requested 120 Hz",
        move, resize, moveErrors.count + resizeErrors.count))
    if !allowLag && (move > 2 || resize > 2) {
      FileHandle.standardError.write(
        Data("DRAG LATENCY FAILED: live attachment exceeds 2 points\n".utf8))
      exit(1)
    }
    NSApp.terminate(nil)
  }
}
