import AppKit
import CoreGraphics
import QuartzCore
import SilliesCore

private struct FixtureFrame: Codable {
  let windowID: Int
  let frame: CGRect
  let time: Double
}

@MainActor
private final class FixtureTitleRegion: NSView {
  var permitsDragging = true
  override func mouseDown(with event: NSEvent) {
    if permitsDragging { window?.performDrag(with: event) }
  }
}

/// Separate-process native window. Its stdout is ground truth, never a tracking input.
@MainActor
final class InputWindowFixture: NSObject, NSWindowDelegate {
  private var window: NSWindow?
  func start() {
    // The fixture represents a document app; accessory agents are intentionally not trackable.
    NSApp.setActivationPolicy(.regular)
    let window = NSWindow(
      contentRect: CGRect(x: 350, y: 250, width: 760, height: 440),
      styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered,
      defer: false)
    window.title = "Sillies · External drag check"
    window.minSize = CGSize(width: 400, height: 250)
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.isMovableByWindowBackground = false
    window.delegate = self
    let label = NSTextField(labelWithString: "Checking movement and resizing across app processes…")
    label.font = .systemFont(ofSize: 18, weight: .medium)
    label.frame = CGRect(x: 35, y: 180, width: 690, height: 50)
    window.contentView?.addSubview(label)
    if let content = window.contentView {
      let header = FixtureTitleRegion(
        frame: CGRect(
          x: 200, y: content.bounds.height - 64, width: content.bounds.width - 200, height: 64))
      header.autoresizingMask = [.width, .minYMargin]
      header.permitsDragging = !ProcessInfo.processInfo.arguments.contains("--blocked-header")
      content.addSubview(header)
    }
    self.window = window
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    publish()
  }
  func windowDidMove(_ notification: Notification) { publish() }
  func windowDidResize(_ notification: Notification) { publish() }
  private func publish() {
    guard let window, window.windowNumber > 0 else { return }
    let message = FixtureFrame(
      windowID: window.windowNumber, frame: window.frame, time: ProcessInfo.processInfo.systemUptime
    )
    if var data = try? JSONEncoder().encode(message) {
      data.append(10)
      FileHandle.standardOutput.write(data)
    }
  }
}

/// Opt-in GUI automation. It moves only the disposable fixture and restores the pointer.
@MainActor
final class ExternalDragCheck: NSObject {
  private enum Phase {
    case waiting, moving, moveSettled, resizing, resizeSettled, topResizing, topResizeSettled
  }
  private let controller: CompanionController
  private let targetBundle: String?
  private let targetHeaderFraction: Double?
  private let expectsStationary: Bool
  private var phaseFrame = CGRect.zero
  private var observedMovement: Double = 0
  private var topHeightChange: Double = 0
  private var targetApplication: NSRunningApplication?
  private var previousApplication: NSRunningApplication?
  private var targetProbe: WindowServerSource?
  private var targetProcessID: pid_t = 0
  private let process = Process()
  private let output = Pipe()
  private var buffer = Data()
  private var latest: FixtureFrame?
  private var phase = Phase.waiting
  private var phaseStarted: Double = 0
  private var link: CADisplayLink?
  private var pointerOrigin = CGPoint.zero
  private var pointerBefore = CGPoint.zero
  private var fractions: [Double] = []
  private var moveErrors: [Double] = []
  private var resizeErrors: [Double] = []
  private var topResizeErrors: [Double] = []
  private var samplesDiscarded = 0
  private var outliers: [String] = []
  private var started: Double = 0

  init(
    controller: CompanionController, targetBundle: String? = nil,
    targetHeaderFraction: Double? = nil, expectsStationary: Bool = false
  ) {
    self.controller = controller
    self.targetBundle = targetBundle
    self.targetHeaderFraction = targetHeaderFraction
    self.expectsStationary = expectsStationary
  }
  private var now: Double { ProcessInfo.processInfo.systemUptime }

  func start() {
    guard CGPreflightPostEventAccess() else {
      print(
        "EXTERNAL DRAG CHECK SKIPPED: macOS event-posting access is unavailable; no permission was requested."
      )
      NSApp.terminate(nil)
      return
    }
    pointerBefore = NSEvent.mouseLocation
    previousApplication = NSWorkspace.shared.frontmostApplication
    if let targetBundle {
      guard
        let application = NSRunningApplication.runningApplications(
          withBundleIdentifier: targetBundle
        ).first
      else {
        fail("Target application is not running: \(targetBundle)")
      }
      targetApplication = application
      targetProcessID = application.processIdentifier
      application.activate()
    } else {
      process.executableURL = Bundle.main.executableURL
      process.arguments = ["--input-fixture"] + (expectsStationary ? ["--blocked-header"] : [])
      process.standardOutput = output
      output.fileHandleForReading.readabilityHandler = { [weak self] handle in
        let data = handle.availableData
        if data.isEmpty {
          handle.readabilityHandler = nil
          return
        }
        DispatchQueue.main.async { [weak self] in self?.receive(data) }
      }
      do { try process.run() } catch { fail("Cannot launch fixture: \(error)") }
      targetProcessID = process.processIdentifier
    }
    if targetBundle != nil || expectsStationary {
      targetProbe = WindowServerSource { [weak self] value in
        DispatchQueue.main.async { [weak self] in
          guard let self, let id = value.windowID, let frame = value.frame else { return }
          let top = NSScreen.screens.first?.frame.maxY ?? 0
          let converted = ScreenCoordinates.appKitRect(
            fromAccessibility: frame, primaryScreenTop: top)
          self.receiveFrame(
            FixtureFrame(windowID: Int(id), frame: converted, time: value.capturedAt))
        }
      }
    }
    started = now
    phaseStarted = now
    guard let screen = NSScreen.main ?? NSScreen.screens.first else {
      fail("No screen available")
    }
    let link = screen.displayLink(target: self, selector: #selector(tick(_:)))
    link.add(to: .main, forMode: .common)
    self.link = link
  }

  private func receive(_ data: Data) {
    buffer.append(data)
    while let newline = buffer.firstIndex(of: 10) {
      let line = buffer.prefix(upTo: newline)
      buffer.removeSubrange(...newline)
      guard let message = try? JSONDecoder().decode(FixtureFrame.self, from: line) else { continue }
      receiveFrame(message)
    }
  }

  private func receiveFrame(_ message: FixtureFrame) {
    latest = message
    guard phase == .moving || phase == .resizing || phase == .topResizing else { return }
    observedMovement = max(
      observedMovement,
      hypot(message.frame.minX - phaseFrame.minX, message.frame.minY - phaseFrame.minY))
    if phase == .topResizing {
      topHeightChange = max(topHeightChange, abs(message.frame.height - phaseFrame.height))
    }
    guard now - message.time < 0.04 else {
      samplesDiscarded += 1
      return
    }
    let visible =
      NSScreen.screens.first?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    let surface = PerchSurface(
      window: message.frame, visibleFrame: visible,
      characterSize: controller.settings.size)
    for (index, attachment) in controller.attachmentDiagnostics.enumerated()
    where fractions.indices.contains(index) {
      let expected = surface.point(at: fractions[index])
      let error = hypot(expected.x - attachment.point.x, expected.y - attachment.point.y)
      if error > 15, outliers.count < 4 {
        outliers.append(
          "\(phase) error=\(error) frame=\(message.frame) tracked=\(String(describing: controller.tracker.windowFrame)) pointer=\(NSEvent.mouseLocation) age=\(now - message.time)"
        )
      }
      switch phase {
      case .moving: moveErrors.append(error)
      case .resizing: resizeErrors.append(error)
      case .topResizing: topResizeErrors.append(error)
      default: break
      }
    }
  }

  @objc private func tick(_ link: CADisplayLink) {
    targetProbe?.refresh(
      processID: targetProcessID, windowID: latest.map { UInt32($0.windowID) },
      discover: latest == nil)
    guard now - started < 16 else {
      fail(
        "Fixture/input timed out at \(phase); tracked=\(String(describing: controller.tracker.windowID)), expected=\(String(describing: latest?.windowID)), frontmostPID=\(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0), fixturePID=\(targetProcessID)"
      )
    }
    if phase != .waiting,
      NSWorkspace.shared.frontmostApplication?.processIdentifier != targetProcessID
    {
      fail("Fixture lost focus; stopping automated input")
    }
    switch phase {
    case .waiting:
      guard let latest, controller.tracker.windowID == UInt32(latest.windowID), now - started > 0.7
      else { return }
      begin(.moving, frame: latest.frame)
    case .moving, .resizing, .topResizing:
      let elapsed = now - phaseStarted
      if elapsed >= 3 {
        post(.leftMouseDragged, at: pointerOrigin)
        post(.leftMouseUp, at: pointerOrigin)
        switch phase {
        case .moving: phase = .moveSettled
        case .resizing: phase = .resizeSettled
        default: phase = .topResizeSettled
        }
        phaseStarted = now
        return
      }
      let dx = phase == .topResizing ? 0 : sin(elapsed * .pi * 2 / 3) * 80
      let dy = sin(elapsed * .pi * 2 / 3) * (phase == .moving ? 20.0 : -40.0)
      post(.leftMouseDragged, at: CGPoint(x: pointerOrigin.x + dx, y: pointerOrigin.y + dy))
    case .moveSettled:
      if now - phaseStarted > 0.45, let latest {
        if targetBundle != nil || expectsStationary {
          finish()
        } else {
          begin(.resizing, frame: latest.frame)
        }
      }
    case .resizeSettled:
      if now - phaseStarted > 0.45, let latest { begin(.topResizing, frame: latest.frame) }
    case .topResizeSettled:
      if now - phaseStarted > 0.45 { finish() }
    }
  }

  private func begin(_ phase: Phase, frame: CGRect) {
    let visible =
      NSScreen.screens.first?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    let surface = PerchSurface(
      window: frame, visibleFrame: visible,
      characterSize: controller.settings.size)
    fractions = controller.attachmentDiagnostics.map { surface.fraction(for: $0.point) }
    phaseFrame = frame
    let companionX =
      targetHeaderFraction.map { frame.minX + frame.width * min(max($0, 0.05), 0.95) }
      ?? controller.attachmentDiagnostics.first?.point.x ?? frame.midX
    switch phase {
    case .moving:
      // The fixture's draggable header begins 200 pt from the left; a four-pet first slot is outside it.
      let headerX = targetBundle == nil ? frame.midX : companionX
      pointerOrigin = CGPoint(x: headerX, y: frame.maxY - (targetBundle == nil ? 44 : 18))
    case .topResizing: pointerOrigin = CGPoint(x: companionX, y: frame.maxY - 2)
    default: pointerOrigin = CGPoint(x: frame.maxX - 2, y: frame.minY + 2)
    }
    self.phase = phase
    phaseStarted = now
    if phase == .topResizing {
      print(
        "TOP INPUT ROUTE: window \(NSWindow.windowNumber(at: pointerOrigin, belowWindowWithWindowNumber: 0)), expected \(latest?.windowID ?? 0)"
      )
    }
    post(.mouseMoved, at: pointerOrigin)
    post(.leftMouseDown, at: pointerOrigin)
  }

  private func post(_ kind: CGEventType, at point: CGPoint) {
    let top = NSScreen.screens.first?.frame.maxY ?? 0
    let cgPoint = CGPoint(x: point.x, y: top - point.y)
    let event = CGEvent(
      mouseEventSource: nil, mouseType: kind, mouseCursorPosition: cgPoint, mouseButton: .left)
    event?.setIntegerValueField(.mouseEventClickState, value: 1)
    event?.post(tap: .cghidEventTap)
  }

  private func finish() {
    let moving = stats(moveErrors)
    let resizing = stats(resizeErrors)
    let topResizing = stats(topResizeErrors)
    if targetBundle == nil && !expectsStationary {
      print(
        String(
          format:
            "EXTERNAL DRAG: move mean %.2f p95 %.2f max %.2f pt (%d); resize mean %.2f p95 %.2f max %.2f pt (%d); stale ground-truth messages discarded %d",
          moving.mean, moving.p95, moving.max, moveErrors.count, resizing.mean, resizing.p95,
          resizing.max, resizeErrors.count, samplesDiscarded))
      print(
        String(
          format:
            "PLAY MODE TOP RESIZE: mean %.2f p95 %.2f max %.2f pt (%d); height changed %.2f pt",
          topResizing.mean, topResizing.p95, topResizing.max, topResizeErrors.count, topHeightChange
        ))
    } else {
      print(
        String(
          format: "TARGET WINDOW %@: mean %.2f p95 %.2f max %.2f pt (%d); actual movement %.2f pt",
          targetBundle ?? "custom header fixture", moving.mean, moving.p95, moving.max,
          moveErrors.count, observedMovement))
    }
    let passed =
      moveErrors.count >= 20 && moving.p95 <= 10
      && (expectsStationary
        ? observedMovement < 1 && moving.max < 2 && controller.tracker.pointerUpdates == 0
        : observedMovement > 40)
      && (targetBundle != nil || expectsStationary
        || (resizeErrors.count >= 20 && topResizeErrors.count >= 20
          && resizing.p95 <= 10 && topResizing.p95 <= 10 && topHeightChange > 15))
    print(
      "TRACKING PATH: pointer updates \(controller.tracker.pointerUpdates), rejected gestures \(controller.tracker.rejectedPointerGestures)"
    )
    for outlier in outliers { print("LIVE ATTACHMENT OUTLIER: \(outlier)") }
    cleanup()
    if !passed {
      fail("Cross-process live attachment exceeds 10-point p95 budget or lacks samples")
    }
    if expectsStationary {
      print(
        "STATIONARY HEADER OK: attempted header drag never moves the companion or its protected window geometry"
      )
    } else {
      print(
        "EXTERNAL DRAG CHECK OK: actual window movement, input priority, and live attachment accuracy"
      )
    }
    NSApp.terminate(nil)
  }

  private func stats(_ values: [Double]) -> (mean: Double, p95: Double, max: Double) {
    let sorted = values.sorted()
    guard let maximum = sorted.last else { return (.infinity, .infinity, .infinity) }
    return (
      values.reduce(0, +) / Double(values.count),
      sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))], maximum
    )
  }

  private func cleanup() {
    link?.invalidate()
    link = nil
    post(.leftMouseUp, at: NSEvent.mouseLocation)
    post(.mouseMoved, at: pointerBefore)
    output.fileHandleForReading.readabilityHandler = nil
    if process.isRunning { process.terminate() }
    targetProbe = nil
    previousApplication?.activate()
  }

  private func fail(_ message: String) -> Never {
    cleanup()
    FileHandle.standardError.write(Data("EXTERNAL DRAG CHECK FAILED: \(message)\n".utf8))
    exit(1)
  }
}
