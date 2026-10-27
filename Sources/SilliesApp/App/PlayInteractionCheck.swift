import AppKit
import CoreGraphics
import QuartzCore
import SilliesCore

/// Opt-in real-input regression. All clicks target Sillies-owned windows and restore focus/pointer.
@MainActor
final class PlayInteractionCheck: NSObject {
  enum Mode { case interaction, dropReturn }
  private enum Phase {
    case waiting, disabledClick, ready, enabled, clicked, pressed, dragged, skillHovered, dropped,
      returned
  }
  private let controller: CompanionController
  private let playground: WindowPlayground
  private let previousApplication: NSRunningApplication?
  private let mode: Mode
  private var background: NSWindow?
  private var link: CADisplayLink?
  private var phase = Phase.waiting
  private var started: Double = 0
  private var phaseStarted: Double = 0
  private var previousPointer = CGPoint.zero
  private var body = CGPoint.zero
  private var initialAttachment = CGPoint.zero
  private var companionIndex = 0
  private var releasePointer = CGPoint.zero
  private var previousTick: Double = 0
  private var dragFrameGaps: [Double] = []
  private var delta: CGPoint {
    mode == .interaction
      ? CGPoint(x: 62, y: 28)
      : CGPoint(x: 80, y: companionIndex.isMultiple(of: 2) ? 90 : -140)
  }
  private static let startupAllowance: Double = 5
  private static let interactionAllowancePerCompanion: Double = 2
  private static let returnAllowancePerCompanion: Double = 3
  private var selectsSkill: Bool {
    mode == .dropReturn && companionIndex == controller.liveCount - 1
  }
  private var timeout: Double {
    Self.startupAllowance + Double(controller.liveCount)
      * (mode == .interaction
        ? Self.interactionAllowancePerCompanion : Self.returnAllowancePerCompanion)
  }

  init(
    controller: CompanionController, playground: WindowPlayground,
    previousApplication: NSRunningApplication?, mode: Mode = .interaction
  ) {
    self.controller = controller
    self.playground = playground
    self.previousApplication = previousApplication
    self.mode = mode
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
    let current = now
    if previousTick > 0, [.pressed, .dragged, .skillHovered, .dropped, .returned].contains(phase) {
      dragFrameGaps.append(current - previousTick)
    }
    previousTick = current
    guard now - started < timeout else {
      fail(
        "Timed out at \(phase); tracked=\(String(describing: controller.tracker.windowID)), target=\(playground.window.windowNumber), attachments=\(controller.attachmentDiagnostics), backgroundKnown=\(background.map { controller.tracker.inputWindowFrames[$0.windowNumber] != nil } ?? false)"
      )
    }
    let elapsed = now - phaseStarted
    switch phase {
    case .waiting:
      guard elapsed > 0.25 else { return }
      require(controller.interactionCounts.isEmpty, "Paused state passes real clicks through")
      controller.settings.paused = false
      controller.playReaction(.userIdle)
      focusPlayground()
      advance(to: .disabledClick)
    case .disabledClick:
      guard ready, elapsed > 0.6 else { return }
      let points = controller.attachmentDiagnostics.map(\.point)
      let distinctPerches = points.enumerated().allSatisfy { index, point in
        points.dropFirst(index + 1).allSatisfy { abs(point.x - $0.x) > controller.settings.size }
      }
      require(
        points.count == controller.liveCount && points.count > 1 && distinctPerches,
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
      if mode == .dropReturn {
        setTarget()
        post(.leftMouseDown, at: body)
        advance(to: .pressed)
        return
      }
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
      let waitsForWheel = mode == .dropReturn && companionIndex >= 2
      guard elapsed > (waitsForWheel ? 0.4 : 0.1) else { return }
      require(
        controller.interactionCounts[.pickedUp, default: 0] == companionIndex + 1,
        "Real drag picks up companion \(companionIndex); events=\(controller.interactionCounts), body=\(body), pointer=\(NSEvent.mouseLocation), attachments=\(controller.attachmentDiagnostics)"
      )
      let points = controller.attachmentDiagnostics
      guard points.indices.contains(companionIndex) else { fail("Companion vanished") }
      let point = points[companionIndex].point
      require(
        hypot(point.x - initialAttachment.x - delta.x, point.y - initialAttachment.y - delta.y) < 2,
        "Companion follows pickup: initial=\(initialAttachment), actual=\(point), expected delta=\(delta), pointer=\(NSEvent.mouseLocation)"
      )
      if selectsSkill {
        let visible =
          playground.window.screen?.visibleFrame
          ?? CGRect(
            x: 0, y: 0, width: 1440, height: 900)
        let layout = RadialSkillMenuLayout(center: destination, visibleFrame: visible)
        guard let focus = layout.items.first(where: { $0.skill == .focus }) else {
          fail("Missing Focus skill")
        }
        releasePointer = focus.center
        post(.leftMouseDragged, at: releasePointer)
        advance(to: .skillHovered)
        return
      }
      releasePointer = destination
      post(.leftMouseUp, at: releasePointer)
      advance(to: .dropped)
    case .skillHovered:
      guard elapsed > 0.08 else { return }
      post(.leftMouseUp, at: releasePointer)
      advance(to: .dropped)
    case .dropped:
      guard elapsed > (mode == .interaction ? 0.15 : 0.04) else { return }
      require(
        controller.interactionCounts[.dropped, default: 0] == companionIndex + 1,
        "Release drops companion \(companionIndex); events=\(controller.interactionCounts), pointer=\(NSEvent.mouseLocation), attachments=\(controller.attachmentDiagnostics)"
      )
      if mode == .dropReturn {
        let point = controller.attachmentDiagnostics[companionIndex].point
        require(
          companionIndex.isMultiple(of: 2)
            ? point.y > initialAttachment.y + 3 : point.y < initialAttachment.y - 20,
          "Return begins at the released position, without an immediate visible snap")
        advance(to: .returned)
        return
      }
      finishCompanion()
    case .returned:
      guard elapsed > 0.38 else { return }
      let point = controller.attachmentDiagnostics[companionIndex].point
      require(
        hypot(point.x - initialAttachment.x, point.y - initialAttachment.y) < 2,
        "Return restores the exact pickup perch, not the release slot: \(initialAttachment) -> \(point)"
      )
      let id = controller.catalog.characters[companionIndex].id
      let binding = controller.skills.binding(for: id)
      if selectsSkill {
        guard case .active(let target, .focus, _, _, _) = binding else {
          fail("Selected Focus skill did not activate")
        }
        require(target.windowID == UInt32(playground.window.windowNumber), "Skill binds its target")
      } else {
        require(!binding.isBound, "An unselected drop keeps following the focused window")
        require(
          controller.diagnostics.visibleHUDCount == 0, "An unselected drop shows no skill bar")
      }
      finishCompanion()
    }
  }

  private func finishCompanion() {
    if companionIndex + 1 < controller.liveCount {
      companionIndex += 1
      // A long full-crew run must not chase a later companion's ambient stroll between input events.
      // Pickup interrupts this resting reaction and still exercises that character's animated clips.
      controller.playReaction(.userIdle)
      post(.mouseMoved, at: previousPointer)
      advance(to: .ready)
      return
    }
    cleanup()
    print("DRAG HANDLERS: \(controller.smoothnessMetrics.summary)")
    let sortedGaps = dragFrameGaps.sorted()
    if let maximum = sortedGaps.last, !sortedGaps.isEmpty {
      let p95 = sortedGaps[min(sortedGaps.count - 1, Int(Double(sortedGaps.count) * 0.95))]
      print(
        String(
          format: "DRAG RESPONSE: p95 %.2f ms, max %.2f ms across %d pickup/drop/return frames",
          p95 * 1000, maximum * 1000, sortedGaps.count))
      if ProcessInfo.processInfo.arguments.contains("--assert-drag-budget") {
        require(maximum < 2.0 / 60, "Pickup, overlays, or drop return stalled over 33 ms")
      }
    }
    if mode == .dropReturn {
      print(
        "DROP RETURN OK: quick falls, below-perch relocation, quiet returns without a skill bar, selected Focus binding"
      )
    } else {
      print(
        "PLAY INPUT OK: all \(controller.liveCount) characters receive real click, pickup, 62×28-point drag, and release over background content"
      )
    }
    NSApp.terminate(nil)
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
