import ApplicationServices
import CoreGraphics
import Foundation

struct WindowObservation: Sendable {
  let processID: pid_t
  let identity: UInt64
  let reason: String
}

/// All AX objects live on `queue`. Only the refresh gate crosses threads, under its lock.
/// A stalled application can block this worker briefly, never the UI or animation clock.
final class AccessibilityWindowSource: @unchecked Sendable {
  private static let messagingTimeoutSeconds: Float = 0.10

  private let queue = DispatchQueue(label: "app.sillies.accessibility", qos: .userInitiated)
  private let gate = NSLock()
  private var refreshPending = false
  private var pendingReason: String?
  private var application: AXUIElement?
  private var window: AXUIElement?
  private var observer: AXObserver?
  private var processID: pid_t = 0
  private var identity: UInt64 = 0
  private let deliver: @Sendable (WindowObservation) -> Void

  init(deliver: @escaping @Sendable (WindowObservation) -> Void) { self.deliver = deliver }

  func observe(processID: pid_t) {
    queue.async { [self] in
      removeObserver()
      self.processID = processID
      guard AXIsProcessTrusted() else {
        publish(reason: "unavailable")
        return
      }
      let app = AXUIElementCreateApplication(processID)
      AXUIElementSetMessagingTimeout(app, Self.messagingTimeoutSeconds)
      application = app
      var created: AXObserver?
      let result = AXObserverCreate(
        processID,
        { _, _, notification, context in
          guard let context else { return }
          let source = Unmanaged<AccessibilityWindowSource>.fromOpaque(context)
            .takeUnretainedValue()
          source.refresh(reason: notification as String)
        }, &created)
      if result == .success, let created {
        observer = created
        let context = Unmanaged.passUnretained(self).toOpaque()
        for name in [
          kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification,
          kAXWindowCreatedNotification,
        ] {
          AXObserverAddNotification(created, app, name as CFString, context)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
      }
      readWindow(reason: "activation")
    }
  }

  func refresh(reason: String = "sample") {
    gate.lock()
    if pendingReason == nil || reason != "sample" { pendingReason = reason }
    guard !refreshPending else {
      gate.unlock()
      return
    }
    refreshPending = true
    gate.unlock()
    queue.async { [self] in drainRefresh() }
  }

  private func drainRefresh() {
    gate.lock()
    let reason = pendingReason ?? "sample"
    pendingReason = nil
    gate.unlock()
    readWindow(reason: reason)
    gate.lock()
    let needsAnotherRead = pendingReason != nil
    if !needsAnotherRead { refreshPending = false }
    gate.unlock()
    // Preserve a trailing update without allowing an unbounded queue of AX reads.
    if needsAnotherRead { queue.async { [self] in drainRefresh() } }
  }

  func stop() {
    queue.async { [self] in
      removeObserver()
      application = nil
    }
  }

  private func removeObserver() {
    if let observer {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }
    observer = nil
    window = nil
    application = nil
  }

  private func readWindow(reason: String) {
    dispatchPrecondition(condition: .notOnQueue(.main))
    guard let application else { return }
    var focused: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &focused)
        == .success,
      let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
    else {
      if window != nil {
        identity &+= 1
        clearTrackedWindow()
      }
      publish(reason: reason)
      return
    }
    let target = unsafeDowncast(focused as AnyObject, to: AXUIElement.self)
    AXUIElementSetMessagingTimeout(target, Self.messagingTimeoutSeconds)
    if window == nil || !CFEqual(window, target) {
      clearTrackedWindow()
      window = target
      identity &+= 1
      if let observer {
        for name in windowNotifications {
          AXObserverAddNotification(
            observer, target, name as CFString, Unmanaged.passUnretained(self).toOpaque())
        }
      }
    }
    publish(reason: reason)
  }

  private var windowNotifications: [String] {
    [
      kAXMovedNotification, kAXResizedNotification, kAXUIElementDestroyedNotification,
      kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
      kAXTitleChangedNotification, kAXSelectedChildrenChangedNotification,
    ]
  }

  private func clearTrackedWindow() {
    if let previous = window, let observer {
      for name in windowNotifications {
        AXObserverRemoveNotification(observer, previous, name as CFString)
      }
    }
    window = nil
  }

  private func publish(reason: String) {
    deliver(WindowObservation(processID: processID, identity: identity, reason: reason))
  }
}
