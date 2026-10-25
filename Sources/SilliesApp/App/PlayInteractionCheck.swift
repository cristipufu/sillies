import AppKit
import CoreGraphics
import QuartzCore
import SilliesCore

/// Opt-in real-input regression. All clicks target Sillies-owned windows and restore focus/pointer.
@MainActor
final class PlayInteractionCheck: NSObject {
  private enum Phase {
    case waiting, disabledClick, ready, enabled, clicked, pressed, dragged, dropped
  }
  private let controller: CompanionController
  private let playground: WindowPlayground
  private let previousApplication: NSRunningApplication?
  private var background: NSWindow?
  private var link: CADisplayLink?
  private var phase = Phase.waiting
  private var started: Double = 0
  private var phaseStarted: Double = 0
  private var previousPointer = CGPoint.zero
  private var body = CGPoint.zero
  private var initialAttachment = CGPoint.zero
  private var companionIndex = 0
  private let delta = CGPoint(x: 62, y: 28)

  init(
    controller: CompanionController, playground: WindowPlayground,
    previousApplication: NSRunningApplication?
  ) {
    self.controller = controller
    self.playground = playground
    self.previousApplication = previousApplication
  }

  private var now: Double { ProcessInfo.processInfo.systemUptime }

  func start() {
    guard CGPreflightPostEventAccess() else {
      print("PLAY INPUT CHECK SKIPPED: event-posting access unavailable; no permission requested")
      NSApp.terminate(nil)
      return
    }
    previousPointer = NSEvent.mouseLocation
    let visible =
      (playground.window.screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
      ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    let background = NSWindow(
      contentRect: visible.insetBy(dx: 12, dy: 20), styleMask: [.titled],
      backing: .buffered, defer: false)
    background.isReleasedWhenClosed = false
    background.title = "Sillies · Interaction test background"
    background.acceptsMouseMovedEvents = true
    self.background = background
    focusPlayground()
    controller.settings.paused = true
    started = now
    phaseStarted = now
    let link = playground.window.displayLink(target: self, selector: #selector(tick(_:)))
    link.add(to: .main, forMode: .common)
    self.link = link
  }

  private func focusPlayground() {
    background?.orderFrontRegardless()
    playground.window.makeKeyAndOrderFront(nil)
    background?.order(.below, relativeTo: playground.window.windowNumber)
    NSApp.activate()
    controller.tracker.refreshFocus()
  }

  @objc private func tick(_ link: CADisplayLink) {
    guard now - started < 8 else { fail("Timed out at \(phase)") }
    let elapsed = now - phaseStarted
    switch phase {
    case .waiting:
      guard elapsed > 0.25 else { return }
      require(controller.interactionCounts.isEmpty, "Paused state passes real clicks through")
      controller.settings.paused = false
      focusPlayground()
      advance(to: .disabledClick)
    case .disabledClick:
      guard ready, elapsed > 0.6 else { return }
      let points = controller.attachmentDiagnostics.map(\.point)
      require(
        points.count == 2 && abs(points[0].x - points[1].x) > controller.settings.size,
        "Characters have distinct initial perches after returning from an unavailable surface")
      let visible =
        (playground.window.screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
        ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
      post(.mouseMoved, at: CGPoint(x: visible.minX + 20, y: visible.minY + 20))
      advance(to: .ready)
    case .ready:
      guard ready, elapsed > 0.5 else { return }
      setTarget()
      advance(to: .enabled)
    case .enabled:
      guard elapsed > 0.1 else { return }
      // No preceding hover update: the first click must work immediately after enabling Play.
      click(at: body)
      advance(to: .clicked)
    case .clicked:
      guard elapsed > 0.15 else { return }
      require(
        controller.interactionCounts[.pet, default: 0] == companionIndex + 1,
        "Real click greets the companion")
      post(.leftMouseDown, at: body)
      advance(to: .pressed)
    case .pressed:
      guard elapsed > 0.05 else { return }
      post(.leftMouseDragged, at: destination)
      advance(to: .dragged)
    case .dragged:
      guard elapsed > 0.1 else { return }
      require(
        controller.interactionCounts[.pickedUp, default: 0] == companionIndex + 1,
        "Real drag picks up the companion"
      )
      let points = controller.attachmentDiagnostics
      guard points.indices.contains(companionIndex) else { fail("Companion vanished") }
      let point = points[companionIndex].point
      require(
        hypot(point.x - initialAttachment.x - delta.x, point.y - initialAttachment.y - delta.y) < 2,
        "Companion follows pickup: initial=\(initialAttachment), actual=\(point), expected delta=\(delta), pointer=\(NSEvent.mouseLocation)"
      )
      post(.leftMouseUp, at: destination)
      advance(to: .dropped)
    case .dropped:
      guard elapsed > 0.15 else { return }
      require(
        controller.interactionCounts[.dropped, default: 0] == companionIndex + 1,
        "Release drops the companion")
      if companionIndex + 1 < controller.liveCount {
        companionIndex += 1
        post(.mouseMoved, at: previousPointer)
        advance(to: .ready)
        return
      }
      cleanup()
      print(
        "PLAY INPUT OK: both characters receive real click, pickup, 62×28-point drag, and release over background content; off passes clicks through"
      )
      NSApp.terminate(nil)
    }
  }

  private var ready: Bool {
    controller.tracker.windowID == UInt32(playground.window.windowNumber)
      && controller.attachmentDiagnostics.first?.edge == .top
      && controller.attachmentDiagnostics.first?.visible == true
      && background.map { controller.tracker.inputWindowFrames[$0.windowNumber] != nil } == true
  }

  private func setTarget() {
    initialAttachment = controller.attachmentDiagnostics[companionIndex].point
    body = CGPoint(x: initialAttachment.x, y: initialAttachment.y + 35)
  }

  private var destination: CGPoint { CGPoint(x: body.x + delta.x, y: body.y + delta.y) }

  private func advance(to phase: Phase) {
    self.phase = phase
    phaseStarted = now
  }

  private func click(at point: CGPoint) {
    post(.leftMouseDown, at: point)
    post(.leftMouseUp, at: point)
  }

  private func post(_ type: CGEventType, at point: CGPoint) {
    let top = NSScreen.screens.first?.frame.maxY ?? 0
    let location = CGPoint(x: point.x, y: top - point.y)
    CGEvent(
      mouseEventSource: nil, mouseType: type, mouseCursorPosition: location, mouseButton: .left)?
      .post(tap: .cghidEventTap)
  }

  private func cleanup() {
    link?.invalidate()
    link = nil
    post(.leftMouseUp, at: NSEvent.mouseLocation)
    post(.mouseMoved, at: previousPointer)
    background?.close()
    previousApplication?.activate()
  }

  private func require(_ condition: Bool, _ message: String) { if !condition { fail(message) } }
  private func fail(_ message: String) -> Never {
    cleanup()
    FileHandle.standardError.write(Data("PLAY INPUT FAILED: \(message)\n".utf8))
    exit(1)
  }
}
