import AppKit

/// Owns native input monitors independently of the window tracking policy.
@MainActor
final class WorkspaceInputMonitor {
  private var global: Any?
  private var local: Any?

  func start(
    receive: @escaping @MainActor (NSEvent) -> Void, released: @escaping @MainActor () -> Void
  ) {
    if global == nil {
      global = NSEvent.addGlobalMonitorForEvents(matching: [
        .leftMouseDown, .leftMouseDragged, .leftMouseUp, .scrollWheel,
      ]) { event in
        MainActor.assumeIsolated { receive(event) }
      }
    }
    if local == nil {
      local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { event in
        released()
        return event
      }
    }
  }

  func stop() {
    if let global { NSEvent.removeMonitor(global) }
    if let local { NSEvent.removeMonitor(local) }
    global = nil
    local = nil
  }

  isolated deinit {
    if let global { NSEvent.removeMonitor(global) }
    if let local { NSEvent.removeMonitor(local) }
  }
}
