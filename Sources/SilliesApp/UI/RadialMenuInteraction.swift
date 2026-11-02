import AppKit
import Carbon
import SilliesCore

/// Event-driven hit regions keep the transparent orbital canvas click-through.
@MainActor final class RadialMenuInteraction {
  private weak var panel: NSPanel?
  private var localRegions: [RadialMenuItemLayout] = []
  private var localMonitor: Any?
  private var globalMonitor: Any?
  private var dismiss: (() -> Void)?
  private var previousMouseMovedAcceptance = false
  var isMonitoring: Bool { localMonitor != nil || globalMonitor != nil }

  func start(panel: NSPanel, localRegions: [RadialMenuItemLayout], dismiss: @escaping () -> Void) {
    stop()
    self.panel = panel
    previousMouseMovedAcceptance = panel.acceptsMouseMovedEvents
    panel.acceptsMouseMovedEvents = true
    self.localRegions = localRegions
    self.dismiss = dismiss
    let pointerEvents: NSEvent.EventTypeMask = [
      .mouseMoved, .leftMouseUp, .leftMouseDown, .rightMouseDown, .otherMouseDown,
    ]
    localMonitor = NSEvent.addLocalMonitorForEvents(matching: pointerEvents.union(.keyDown)) {
      [weak self] event in
      guard let self else { return event }
      return self.handleLocalEvent(event)
    }
    globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: pointerEvents) {
      [weak self] event in
      MainActor.assumeIsolated { self?.handlePointer(event.type, at: NSEvent.mouseLocation) }
    }
    refresh(at: NSEvent.mouseLocation)
  }
  func handleLocalEvent(_ event: NSEvent) -> NSEvent? {
    if event.type == .keyDown {
      guard event.keyCode == UInt16(kVK_Escape) else { return event }
      dismiss?()
      return nil
    }
    let point =
      event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
    handlePointer(event.type, at: point)
    return event
  }
  func refresh(at point: CGPoint) {
    guard let panel else { return }
    let local = panel.convertPoint(fromScreen: point)
    panel.ignoresMouseEvents = !localRegions.contains { $0.contains(local) }
  }
  func handlePointer(_ type: NSEvent.EventType, at point: CGPoint) {
    refresh(at: point)
    if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(type),
      panel?.ignoresMouseEvents == true
    {
      dismiss?()
    }
  }
  func stop() {
    if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
    localMonitor = nil
    globalMonitor = nil
    panel?.ignoresMouseEvents = true
    panel?.acceptsMouseMovedEvents = previousMouseMovedAcceptance
    panel = nil
    localRegions = []
    dismiss = nil
  }
  isolated deinit { stop() }
}
