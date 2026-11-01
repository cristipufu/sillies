import AppKit
import SilliesCore

/// Observes mouse gestures without consuming them or dismissing on loss of key-window status.
@MainActor final class ConversationWindowDismissal {
  private weak var window: NSWindow?
  private var gesture = OutsideClickDismissal()
  private var dismiss: (() -> Void)?
  private var localMonitor: Any?
  private var globalMonitor: Any?
  var isMonitoring: Bool { localMonitor != nil || globalMonitor != nil }

  func start(window: NSWindow, dismiss: @escaping () -> Void) {
    stop()
    self.window = window
    self.dismiss = dismiss
    let events: NSEvent.EventTypeMask = [
      .leftMouseDown, .rightMouseDown, .otherMouseDown,
      .leftMouseUp, .rightMouseUp, .otherMouseUp,
      .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
    ]
    localMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
      self?.handleLocalEvent(event)
      return event
    }
    globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] event in
      MainActor.assumeIsolated {
        self?.handle(event, at: NSEvent.mouseLocation)
      }
    }
  }

  func handleLocalEvent(_ event: NSEvent) {
    if owns(event.window) {
      gesture.cancel()
      return
    }
    handle(
      event,
      at: event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation)
  }

  private func owns(_ candidate: NSWindow?) -> Bool {
    if candidate?.level == .popUpMenu { return true }
    var ancestor = candidate
    while let current = ancestor {
      if current === window { return true }
      ancestor = current.parent ?? current.sheetParent
    }
    return false
  }

  private func handle(_ event: NSEvent, at point: CGPoint) {
    guard window != nil, window?.attachedSheet == nil else {
      gesture.cancel()
      return
    }
    switch event.type {
    case .leftMouseDown, .rightMouseDown, .otherMouseDown:
      gesture.begin(at: point, button: event.buttonNumber)
    case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
      gesture.cancel()
    case .leftMouseUp, .rightMouseUp, .otherMouseUp:
      if gesture.release(at: point, button: event.buttonNumber) {
        let action = dismiss
        stop()
        action?()
      }
    default: break
    }
  }

  func stop() {
    if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
    localMonitor = nil
    globalMonitor = nil
    window = nil
    dismiss = nil
    gesture.cancel()
  }

  isolated deinit {
    if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
  }
}
