import AppKit
import SilliesCore

/// Waits for presented geometry to settle; fixed sleeps are unreliable during native animations.
@MainActor
final class WindowIntegrationCheck {
  private enum Stage: Int { case top, resize, move, sides, minimize, restore, close }
  private let controller: CompanionController
  private let playground: WindowPlayground
  private var stage = Stage.top
  private var deadline: Double = 0
  private var stableSince: Double?
  private var timer: Timer?
  private var settledBeforeResize = 0
  private var landingsBeforeResize = 0

  init(controller: CompanionController, playground: WindowPlayground) {
    self.controller = controller
    self.playground = playground
  }

  func start() {
    deadline = time + 6
    // RunLoop retains the timer/session until finish invalidates it.
    let timer = Timer(timeInterval: 0.05, repeats: true) { [self] _ in
      MainActor.assumeIsolated { tick() }
    }
    self.timer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  private var time: Double { ProcessInfo.processInfo.systemUptime }

  private func tick() {
    guard time < deadline else {
      fail(
        "Timed out at \(stage): target \(playground.targetFrame), tracked \(String(describing:controller.tracker.windowFrame))"
      )
    }
    let ready: Bool
    if stage == .minimize {
      require(
        controller.tracker.windowID != UInt32(playground.window.windowNumber),
        "A minimizing window must never be reattached during its Dock animation")
    }
    if stage == .close || stage == .minimize {
      ready = controller.tracker.windowFrame == nil
    } else if let frame = controller.tracker.windowFrame {
      let target = playground.targetFrame
      ready =
        controller.tracker.windowID == UInt32(playground.window.windowNumber)
        && abs(frame.minX - target.minX) < 2 && abs(frame.minY - target.minY) < 2
        && abs(frame.width - target.width) < 2 && abs(frame.height - target.height) < 2
    } else {
      ready = false
    }
    guard ready else {
      stableSince = nil
      return
    }
    if stage == .resize {
      guard controller.tracker.eventCounts[.windowSettled, default: 0] > settledBeforeResize,
        controller.playedAnimations[.land, default: 0] > landingsBeforeResize
      else { return }
    }
    if stableSince == nil { stableSince = time }
    guard let since = stableSince, time - since >= 0.45 else { return }
    verifyAndAdvance()
  }

  private func verifyAndAdvance() {
    if stage != .close && stage != .minimize {
      guard let frame = controller.tracker.windowFrame else { fail("Missing window") }
      let attachments = controller.attachmentDiagnostics
      require(
        attachments.count == controller.settings.enabledCharacters.count
          && attachments.allSatisfy(\.visible),
        "All characters visible at \(stage)")
      require(
        attachments.allSatisfy { !frame.contains($0.point) },
        "Characters remain outside the window at \(stage)")
      require(
        attachments.allSatisfy { $0.frame.intersection(frame).isEmpty },
        "Native panel bounds exclude the document and title bar at \(stage)")
    }
    switch stage {
    case .top:
      require(
        controller.attachmentDiagnostics.allSatisfy { $0.edge == .top }, "Characters stand on top")
      for attachment in controller.attachmentDiagnostics {
        _ = controller.blockingCompanionCount(
          at: CGPoint(x: attachment.point.x, y: attachment.point.y + 35))
        let receiver = NSWindow.windowNumber(
          at: CGPoint(x: attachment.point.x, y: attachment.point.y - 18),
          belowWindowWithWindowNumber: 0)
        require(
          receiver == playground.window.windowNumber,
          "WindowServer must route title-bar clicks correctly even before hover updates; receiver=\(receiver)"
        )
        require(
          controller.blockingCompanionCount(
            at: CGPoint(x: attachment.point.x, y: attachment.point.y - 2)) == 0,
          "Native top resize border passes input through in Play mode")
        require(
          controller.blockingCompanionCount(
            at: CGPoint(x: attachment.point.x, y: attachment.point.y - 18)) == 0,
          "Native title bar passes input through inside the transparent panel")
      }
      controller.exportWindowScene(playground.window, name: "window-top")
      settledBeforeResize = controller.tracker.eventCounts[.windowSettled, default: 0]
      landingsBeforeResize = controller.playedAnimations[.land, default: 0]
      playground.squeeze()
    case .resize:
      require(
        controller.tracker.eventCounts[.windowResized, default: 0] > 0, "Real resize detected")
      require(controller.playedAnimations[.brace, default: 0] > 0, "Mochi braces")
      require(controller.playedAnimations[.scramble, default: 0] > 0, "Kiko scrambles")
      require(controller.playedAnimations[.land, default: 0] > 0, "The crew settles after resizing")
      playground.nudge()
    case .move:
      require(
        controller.tracker.eventCounts[.windowMoved, default: 0] > 0, "Real movement detected")
      playground.makeTall()
    case .sides:
      require(
        controller.attachmentDiagnostics.allSatisfy { $0.pose.isHanging && $0.upright },
        "Side characters hang upright by their hands")
      require(
        controller.attachmentDiagnostics.allSatisfy { $0.edge == .left || $0.edge == .right },
        "Tall window uses outside edges")
      controller.exportWindowScene(playground.window, name: "window-sides")
      playground.window.miniaturize(nil)
    case .minimize:
      require(
        controller.attachmentDiagnostics.allSatisfy { !$0.visible },
        "Minimized windows finish their exit and remain hidden")
      playground.window.deminiaturize(nil)
      playground.window.makeKeyAndOrderFront(nil)
    case .restore:
      require(controller.attachmentDiagnostics.allSatisfy(\.visible), "Restore shows the crew")
      playground.window.close()
    case .close:
      require(controller.tracker.eventCounts[.windowDisappeared, default: 0] > 0, "Close detected")
      timer?.invalidate()
      timer = nil
      print(
        "WINDOW TEST OK: real focused window, exact top-edge geometry, resize/move acting, settling, exterior sides, minimize/restore, close; Accessibility \(controller.tracker.hasAccessibility ? "on" : "off")"
      )
      NSApp.terminate(nil)
      return
    }
    if let nextStage = Stage(rawValue: stage.rawValue + 1) {
      stage = nextStage
    }
    deadline = time + 6
    stableSince = nil
  }

  private func require(_ condition: Bool, _ message: String) { if !condition { fail(message) } }
  private func fail(_ message: String) -> Never {
    let events = controller.tracker.eventCounts.map { "\($0.key.rawValue)=\($0.value)" }.sorted()
    let clips = controller.playedAnimations.map { "\($0.key.rawValue)=\($0.value)" }.sorted()
    FileHandle.standardError.write(
      Data("WINDOW TEST FAILED: \(message); events \(events); clips \(clips)\n".utf8))
    exit(1)
  }
}
