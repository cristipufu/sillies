import AppKit
import QuartzCore
import SilliesCore

/// Samples attachment error during every update, rather than waiting for the window to settle.
@MainActor
final class DragLatencyCheck: NSObject {
  private static let phaseDuration: Double = 1.25
  private static let millisecondsPerSecond: Double = 1000
  private static let maximumFrameGap: Double = 2.0 / 60
  private let controller: CompanionController
  private let playground: WindowPlayground
  private let allowLag: Bool
  private var link: CADisplayLink?
  private var base = CGRect.zero
  private var fractions: [Double] = []
  private var started: Double = 0
  private var moveErrors: [Double] = []
  private var resizeErrors: [Double] = []
  private var previousTick: Double?
  private var frameGaps: [Double] = []

  init(controller: CompanionController, playground: WindowPlayground, allowLag: Bool) {
    self.controller = controller
    self.playground = playground
    self.allowLag = allowLag
    super.init()
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
      controller.smoothnessMetrics.isEnabled = true
      controller.smoothnessMetrics.reset()
      let link = playground.window.displayLink(target: self, selector: #selector(tick(_:)))
      let maximum = Float(playground.window.screen?.maximumFramesPerSecond ?? 60)
      link.preferredFrameRateRange = CAFrameRateRange(
        minimum: maximum, maximum: maximum, preferred: maximum)
      self.link = link
      link.add(to: .main, forMode: .common)
    }
  }

  @objc private func tick(_ link: CADisplayLink) {
    let time = ProcessInfo.processInfo.systemUptime
    if let previousTick { frameGaps.append(time - previousTick) }
    previousTick = time
    let elapsed = time - started
    guard elapsed < Self.phaseDuration * 2 else {
      finish()
      return
    }
    var frame = base
    if elapsed < Self.phaseDuration {
      frame.origin.x += sin(elapsed * 5) * 110
      frame.origin.y += sin(elapsed * 6) * 30
    } else {
      frame.size.width += sin((elapsed - Self.phaseDuration) * 5) * 100
      frame.size.height += sin((elapsed - Self.phaseDuration) * 6) * 35
    }
    playground.window.setFrame(frame, display: true)
    let actual = playground.window.frame
    let visible =
      (playground.window.screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
      ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    let surface = PerchSurface(
      window: actual, visibleFrame: visible, characterSize: controller.settings.size)
    let expectedPositions = PerchSpacing.restingPoints(
      near: fractions.map { surface.point(at: $0) }, on: surface)
    for (index, attachment) in controller.attachmentDiagnostics.enumerated() {
      guard expectedPositions.indices.contains(index), let expected = expectedPositions[index]
      else { continue }
      let error = hypot(expected.x - attachment.point.x, expected.y - attachment.point.y)
      // Resize may legitimately redistribute a crowded crew. Carry the independently
      // calculated slots forward; never derive the next expectation from measured positions.
      fractions[index] = surface.fraction(for: expected)
      if elapsed < Self.phaseDuration {
        moveErrors.append(error)
      } else {
        resizeErrors.append(error)
      }
    }
  }

  private func finish() {
    link?.invalidate()
    link = nil
    let move = moveErrors.max() ?? .infinity
    let resize = resizeErrors.max() ?? .infinity
    print(
      String(
        format:
          "DRAG LATENCY: move max %.2f pt, resize max %.2f pt; %d display-linked live attachment samples",
        move, resize, moveErrors.count + resizeErrors.count))
    print("INTERACTION HANDLERS: \(controller.smoothnessMetrics.summary)")
    let gaps = frameGaps.sorted()
    let maximumGap = gaps.last ?? .infinity
    let p95 = gaps.isEmpty ? .infinity : gaps[min(gaps.count - 1, Int(Double(gaps.count) * 0.95))]
    print(
      String(
        format: "LIVE FRAME GAPS: p95 %.2f ms, max %.2f ms (%d frames)",
        p95 * Self.millisecondsPerSecond, maximumGap * Self.millisecondsPerSecond, gaps.count))
    if !allowLag && (move > 2 || resize > 2) {
      FileHandle.standardError.write(
        Data("DRAG LATENCY FAILED: live attachment exceeds 2 points\n".utf8))
      exit(1)
    }
    if ProcessInfo.processInfo.arguments.contains("--assert-drag-budget"),
      maximumGap > Self.maximumFrameGap
    {
      FileHandle.standardError.write(
        Data("LIVE FRAME BUDGET FAILED: callback gap exceeds 33 ms\n".utf8))
      exit(1)
    }
    if ProcessInfo.processInfo.arguments.contains("--assert-drag-budget") {
      assertHandlerBudgets()
    }
    NSApp.terminate(nil)
  }

  private func assertHandlerBudgets() {
    for path: InteractionSmoothnessMetrics.Path in [.windowMove, .windowResize] {
      guard controller.smoothnessMetrics.isWithinBudget(for: path) else {
        fputs("INTERACTION HANDLER BUDGET FAILED: \(path.rawValue)\n", stderr)
        exit(1)
      }
    }
  }
}
