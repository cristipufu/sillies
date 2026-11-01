import AppKit
import Carbon
import SilliesCore

/// Event-driven hit regions keep the transparent orbital canvas click-through.
@MainActor final class RadialMenuInteraction {
  private weak var panel: NSPanel?
  private var regions: [RadialMenuItemLayout] = []
  private var localMonitor: Any?
  private var globalMonitor: Any?
  private var dismiss: (() -> Void)?
  var isMonitoring: Bool { localMonitor != nil || globalMonitor != nil }

  func start(panel: NSPanel, regions: [RadialMenuItemLayout], dismiss: @escaping () -> Void) {
    stop()
    self.panel = panel
    self.regions = regions
    self.dismiss = dismiss
    let pointerEvents: NSEvent.EventTypeMask = [
      .mouseMoved, .leftMouseUp, .leftMouseDown, .rightMouseDown, .otherMouseDown,
    ]
    localMonitor = NSEvent.addLocalMonitorForEvents(matching: pointerEvents.union(.keyDown)) {
      [weak self] event in
      guard let self else { return event }
      if event.type == .keyDown {
        if event.keyCode == UInt16(kVK_Escape) {
          self.dismiss?()
          return nil
        }
      } else {
        self.handlePointer(event.type, at: NSEvent.mouseLocation)
      }
      return event
    }
    globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: pointerEvents) {
      [weak self] event in
      MainActor.assumeIsolated { self?.handlePointer(event.type, at: NSEvent.mouseLocation) }
    }
    refresh(at: NSEvent.mouseLocation)
  }
  func refresh(at point: CGPoint) {
    panel?.ignoresMouseEvents = !regions.contains { $0.contains(point) }
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
    panel = nil
    regions = []
    dismiss = nil
  }
  isolated deinit {
    if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
  }
}
