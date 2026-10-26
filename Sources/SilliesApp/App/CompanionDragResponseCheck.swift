import AppKit
import QuartzCore
import SilliesCore

/// Repeated mascot-only input over an explicitly named running app. No keys or target-window edits.
@MainActor
final class CompanionDragResponseCheck: NSObject {
  private enum Phase { case waiting, ready, pressed, approaching, dragging, returned }
  private let controller: CompanionController
  private let targetBundle: String
  private let previousApplication = NSWorkspace.shared.frontmostApplication
  private let previousPointer = NSEvent.mouseLocation
  private var link: CADisplayLink?
  private var phase = Phase.waiting
  private var started: Double = 0
  private var phaseStarted: Double = 0
  private var previousTick: Double = 0
  private var gaps: [Double] = []
  private var borderGaps: [Double] = []
  private var cycle = 0
  private var index = 0
  private var body = CGPoint.zero
  private var destination = CGPoint.zero
  private var pointer = CGPoint.zero
  private var enteredWindow: UInt32?
  private var observedWheel = false
  private var mouseIsDown = false
  private var now: Double { ProcessInfo.processInfo.systemUptime }

  init(controller: CompanionController, targetBundle: String) {
    self.controller = controller
    self.targetBundle = targetBundle
  }

  func start() {
    guard CGPreflightPostEventAccess() else {
      print("COMPANION DRAG CHECK SKIPPED: existing event-posting access required")
      NSApp.terminate(nil)
      return
    }
    guard
      let app = NSRunningApplication.runningApplications(withBundleIdentifier: targetBundle).first,
      let screen = NSScreen.main ?? NSScreen.screens.first
    else { fail("Target app is not running or no display is available") }
    app.activate()
    controller.tracker.refreshFocus()
    started = now
    phaseStarted = now
    let link = screen.displayLink(target: self, selector: #selector(tick(_:)))
    link.add(to: .main, forMode: .common)
    self.link = link
  }

  @objc private func tick(_ displayLink: CADisplayLink) {
    let time = now
    guard time - started < 20 else { fail("Timed out at \(phase)") }
    guard
      NSWorkspace.shared.frontmostApplication?.bundleIdentifier == targetBundle || phase == .waiting
    else { fail("Target app lost focus; input stopped") }
    if previousTick > 0, phase == .pressed || phase == .approaching || phase == .dragging {
      gaps.append(time - previousTick)
      if phase == .dragging || (phase == .approaching && time - phaseStarted > 0.9) {
        borderGaps.append(time - previousTick)
      }
    }
    previousTick = time
    let elapsed = time - phaseStarted
    switch phase {
    case .waiting:
      guard elapsed > 0.6, controller.tracker.bundleIdentifier == targetBundle,
        controller.tracker.windowFrame != nil,
        controller.attachmentDiagnostics.contains(where: \.visible)
      else { return }
      advance(.ready)
    case .ready:
      guard elapsed > 0.15, let frame = controller.tracker.windowFrame,
        let chosen = controller.attachmentDiagnostics.firstIndex(where: \.visible)
      else { return }
      index = chosen
      let pet = controller.attachmentDiagnostics[index]
      let vertical = pet.edge == .left || pet.edge == .right
      let scale =
        (vertical ? pet.frame.height : pet.frame.width)
        / CompanionWindowLayout.runtimeCanvasDimension
      switch pet.edge {
      case .left: body = CGPoint(x: pet.point.x - 48 * scale, y: pet.point.y - 41 * scale)
      case .right: body = CGPoint(x: pet.point.x + 48 * scale, y: pet.point.y - 41 * scale)
      default: body = CGPoint(x: pet.point.x, y: pet.point.y + 55 * scale)
      }
      guard controller.interactiveArtworkCount(at: body) == 1 else {
        fail("No exclusive companion artwork at pickup point; no target input posted")
      }
      destination = CGPoint(
        x: min(max(body.x, frame.minX + 2), frame.maxX - 2),
        y: min(max(body.y, frame.minY + 2), frame.maxY - 2))
      enteredWindow = controller.tracker.windowID
      observedWheel = false
      post(.leftMouseDown, at: body)
      advance(.pressed)
    case .pressed:
      guard elapsed > 0.04 else { return }
      advance(.approaching)
    case .approaching:
      let progress = min(elapsed / 1.6, 1)
      pointer = CGPoint(
        x: body.x + (destination.x - body.x) * progress,
        y: body.y + (destination.y - body.y) * progress)
      post(.leftMouseDragged, at: pointer)
      if progress >= 1 { advance(.dragging) }
    case .dragging:
      guard controller.interactionCounts[.pickedUp, default: 0] == cycle + 1 else {
        if elapsed > 0.15 { fail("Companion did not receive pickup; input stopped") }
        return
      }
      if elapsed > 0.5 {
        let overlay = controller.dragOverlayDiagnostics
        observedWheel =
          observedWheel || (overlay.wheel && overlay.highlight && overlay.windowID == enteredWindow)
      }
      if elapsed < 1 {
        pointer = CGPoint(
          x: destination.x + sin(elapsed * 14) * 0.5, y: destination.y + cos(elapsed * 14) * 0.5)
        post(.leftMouseDragged, at: pointer)
      } else {
        guard observedWheel else {
          fail("Expected target highlight and radial wheel were not shown")
        }
        post(.leftMouseUp, at: pointer)
        advance(.returned)
      }
    case .returned:
      guard elapsed > 0.5 else { return }
      guard controller.interactionCounts[.dropped, default: 0] == cycle + 1 else {
        fail("Missing release")
      }
      let id = controller.catalog.characters[index].id
      controller.skills.unbind(companionID: id)
      cycle += 1
      if cycle < 5 {
        advance(.ready)
      } else {
        let sorted = gaps.sorted()
        let p95 =
          sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        print(
          String(
            format:
              "COMPANION DRAG RESPONSE %@: p95 %.2f ms, max %.2f ms, %d drag frames, %d repeated entries",
            targetBundle, p95 * 1000, (sorted.last ?? 0) * 1000, sorted.count, cycle))
        let border = borderGaps.sorted()
        let borderP95 =
          border.isEmpty ? 0 : border[min(border.count - 1, Int(Double(border.count) * 0.95))]
        print(
          String(
            format: "BORDER/WHEEL: p95 %.2f ms, max %.2f ms, %d frames",
            borderP95 * 1000, (border.last ?? 0) * 1000, border.count))
        print("DRAG STAGES: \(controller.dragTimingSummary)")
        cleanup()
        NSApp.terminate(nil)
      }
    }
  }

  private func advance(_ phase: Phase) {
    self.phase = phase
    phaseStarted = now
  }

  private func post(_ type: CGEventType, at point: CGPoint) {
    if type == .leftMouseDown { mouseIsDown = true }
    if type == .leftMouseUp { mouseIsDown = false }
    let top = NSScreen.screens.first?.frame.maxY ?? 0
    CGEvent(
      mouseEventSource: nil, mouseType: type,
      mouseCursorPosition: CGPoint(x: point.x, y: top - point.y), mouseButton: .left)?.post(
        tap: .cghidEventTap)
  }

  private func cleanup() {
    link?.invalidate()
    link = nil
    if mouseIsDown { post(.leftMouseUp, at: pointer) }
    post(.mouseMoved, at: previousPointer)
    previousApplication?.activate()
  }

  private func fail(_ message: String) -> Never {
    cleanup()
    FileHandle.standardError.write(Data("COMPANION DRAG CHECK FAILED: \(message)\n".utf8))
    exit(1)
  }
}
