import AppKit
import Carbon

/// Accessory apps cannot rely on transient-popover activation alone for outside clicks.
@MainActor final class ControlCenterDismissal {
  private weak var popover: NSPopover?
  private weak var statusButton: NSView?
  private var localMonitor: Any?
  private var globalMonitor: Any?
  var isMonitoring: Bool { localMonitor != nil || globalMonitor != nil }

  func start(popover: NSPopover, statusButton: NSView) {
    stop()
    self.popover = popover
    self.statusButton = statusButton
    localMonitor = NSEvent.addLocalMonitorForEvents(matching: [
      .leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown,
    ]) { [weak self] event in
      guard let self else { return event }
      return self.handleLocalEvent(event)
    }
    globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [
      .leftMouseDown, .rightMouseDown, .otherMouseDown,
    ]) { [weak self] _ in
      MainActor.assumeIsolated { self?.dismiss() }
    }
  }

  func handleLocalEvent(_ event: NSEvent) -> NSEvent? {
    guard let popover, popover.isShown else { return event }
    if event.type == .keyDown {
      guard event.keyCode == UInt16(kVK_Escape) else { return event }
      dismiss()
      return nil
    }
    if let window = event.window {
      if window === popover.contentViewController?.view.window { return event }
      // Picker menus and child panels belong to the open control center.
      if window.parent === popover.contentViewController?.view.window { return event }
      if window.level == .popUpMenu { return event }
      if let statusButton, window === statusButton.window,
        statusButton.bounds.contains(statusButton.convert(event.locationInWindow, from: nil))
      {
        return event
      }
    }
    dismiss()
    return event
  }

  private func dismiss() {
    let shown = popover
    stop()
    shown?.performClose(nil)
  }
  func stop() {
    if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
    localMonitor = nil
    globalMonitor = nil
    popover = nil
    statusButton = nil
  }
  isolated deinit {
    if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
  }
}
