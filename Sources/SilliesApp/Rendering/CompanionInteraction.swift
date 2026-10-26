import AppKit
import SilliesCore

/// Play mode owns only opaque artwork under the pointer, never the transparent panel canvas.
@MainActor
final class CompanionInteraction {
  struct Target {
    let panel: CompanionPanel
    let view: CompanionView
    let isDragging: () -> Bool
    var isReturning: () -> Bool = { false }
  }

  private var targets: [Target] = []
  private var globalMonitor: Any?
  private var localMonitor: Any?
  private var lastPointerLocation = NSEvent.mouseLocation
  private(set) var isEnabled = false
  private(set) var monitorInstallations = 0

  func configure(enabled: Bool, targets: [Target]) {
    guard enabled else {
      stop()
      return
    }
    self.targets = targets
    isEnabled = true
    if globalMonitor == nil {
      monitorInstallations += 1
      globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseUp]) {
        [weak self] _ in
        MainActor.assumeIsolated { self?.refresh(at: NSEvent.mouseLocation) }
      }
    }
    if localMonitor == nil {
      localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseUp]) {
        [weak self] event in
        self?.refresh(at: NSEvent.mouseLocation)
        return event
      }
    }
    refresh(at: NSEvent.mouseLocation)
  }

  func stop() {
    if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
    if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    globalMonitor = nil
    localMonitor = nil
    isEnabled = false
    for target in targets { target.panel.ignoresMouseEvents = true }
    targets.removeAll()
  }

  func refresh() {
    refresh(at: lastPointerLocation)
  }

  func refresh(at point: CGPoint) {
    lastPointerLocation = point
    for target in targets {
      let eligible =
        isEnabled && target.panel.isVisible && !target.isReturning()
        && (target.isDragging()
          || !target.panel.frame.contains(point)
          || target.view.containsInteractiveArtwork(at: point))
      // Keep panels ready before the pointer arrives; inside the panel, only opaque artwork intercepts clicks.
      if target.panel.ignoresMouseEvents == eligible {
        target.panel.ignoresMouseEvents = !eligible
      }
    }
  }
}
