import ApplicationServices
import CoreGraphics
import Foundation

struct AccessibilityWindowRoleSnapshot: Sendable, Equatable {
  var standardWindowFrames: [CGRect] = []
  var nonStandardWindowFrames: [CGRect] = []
  var hasVerifiedWindowList = false
  var hasExactStandardWindowFrames = false
  var focusedStandardWindowFrame: CGRect?

  var isUnavailable: Bool {
    !hasVerifiedWindowList && standardWindowFrames.isEmpty && nonStandardWindowFrames.isEmpty
  }

  init(
    standardWindowFrames: [CGRect] = [],
    nonStandardWindowFrames: [CGRect] = [],
    hasVerifiedWindowList: Bool = false,
    hasExactStandardWindowFrames: Bool? = nil
  ) {
    self.standardWindowFrames = standardWindowFrames
    self.nonStandardWindowFrames = nonStandardWindowFrames
    self.hasVerifiedWindowList = hasVerifiedWindowList
    self.hasExactStandardWindowFrames = hasExactStandardWindowFrames ?? hasVerifiedWindowList
  }
}

struct WindowObservation: Sendable {
  let processID: pid_t
  let identity: UInt64
  let reason: String
  var focusedFrame: CGRect?
  var roleSnapshot: AccessibilityWindowRoleSnapshot?
}

/// All AX objects live on `queue`. Only the refresh gate crosses threads, under its lock.
/// A stalled application can block this worker briefly, never the UI or animation clock.
final class AccessibilityWindowSource: @unchecked Sendable {
  static let activationReason = "activation"
  static let sampleReason = "sample"
  static let unavailableReason = "unavailable"
  private static let messagingTimeoutSeconds: Float = 0.10
  private static let lookupMessagingTimeoutSeconds: Float = 0.05
  private static let maxInspectedWindowCount = 12

  private struct InspectedWindow {
    let element: AXUIElement
    let frame: CGRect
    let isStandardWindow: Bool
  }

  private let queue = DispatchQueue(label: "app.sillies.accessibility", qos: .userInitiated)
  private let gate = NSLock()
  private var refreshPending = false
  private var pendingReason: String?
  private var requestedProcessID: pid_t = 0
  private var observePending = false
  private var application: AXUIElement?
  private var window: AXUIElement?
  private var observer: AXObserver?
  private var processID: pid_t = 0
  private var identity: UInt64 = 0
  private var cachedRoleSnapshot: AccessibilityWindowRoleSnapshot?
  private let deliver: @Sendable (WindowObservation) -> Void

  init(deliver: @escaping @Sendable (WindowObservation) -> Void) { self.deliver = deliver }

  func observe(processID: pid_t) {
    gate.lock()
    requestedProcessID = processID
    pendingReason = nil
    guard !observePending else {
      gate.unlock()
      return
    }
    observePending = true
    gate.unlock()
    queue.async { [self] in drainObserve() }
  }

  private func drainObserve() {
    gate.lock()
    let targetPID = requestedProcessID
    gate.unlock()
    removeObserver()
    processID = targetPID
    guard targetPID != 0 else {
      finishObserveDrain()
      return
    }
    guard AXIsProcessTrusted() else {
      publish(reason: Self.unavailableReason)
      finishObserveDrain()
      return
    }
    let app = AXUIElementCreateApplication(targetPID)
    AXUIElementSetMessagingTimeout(app, Self.messagingTimeoutSeconds)
    application = app
    var created: AXObserver?
    let result = AXObserverCreate(
      targetPID,
      { _, _, notification, context in
        guard let context else { return }
        let source = Unmanaged<AccessibilityWindowSource>.fromOpaque(context)
          .takeUnretainedValue()
        source.refresh(reason: notification as String)
      }, &created)
    if result == .success, let created, isCurrentRequestedProcess(targetPID) {
      observer = created
      let context = Unmanaged.passUnretained(self).toOpaque()
      for name in applicationNotifications {
        guard isCurrentRequestedProcess(targetPID) else { break }
        AXObserverAddNotification(created, app, name as CFString, context)
      }
      if isCurrentRequestedProcess(targetPID) {
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
      }
    }
    if isCurrentRequestedProcess(targetPID) {
      readWindow(reason: Self.activationReason)
    }
    finishObserveDrain()
  }

  private func finishObserveDrain() {
    gate.lock()
    let needsAnotherObserve = requestedProcessID != processID
    if !needsAnotherObserve { observePending = false }
    gate.unlock()
    if needsAnotherObserve { queue.async { [self] in drainObserve() } }
  }

  private func isCurrentRequestedProcess(_ pid: pid_t) -> Bool {
    gate.lock()
    let matches = requestedProcessID == pid
    gate.unlock()
    return matches
  }

  func refresh(reason: String = AccessibilityWindowSource.sampleReason) {
    gate.lock()
    if let existing = pendingReason {
      if Self.notificationPriority(for: reason) >= Self.notificationPriority(for: existing) {
        pendingReason = reason
      }
    } else {
      pendingReason = reason
    }
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
    let reason = pendingReason ?? Self.sampleReason
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
    gate.lock()
    requestedProcessID = 0
    pendingReason = nil
    gate.unlock()
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
    cachedRoleSnapshot = nil
  }

  private func readWindow(reason: String) {
    dispatchPrecondition(condition: .notOnQueue(.main))
    guard let application, isCurrentRequestedProcess(processID) else { return }
    if Self.isNonStructuralWindowNotification(reason), window != nil {
      if reason == kAXMovedNotification || reason == kAXResizedNotification {
        cachedRoleSnapshot?.hasExactStandardWindowFrames = false
      }
      publish(reason: reason, roleSnapshot: cachedRoleSnapshot)
      return
    }
    let focusedElement = Self.copyWindowAttribute(
      kAXFocusedWindowAttribute, from: application, timeout: Self.messagingTimeoutSeconds)
    guard isCurrentRequestedProcess(processID) else { return }
    let evaluation = Self.evaluateApplicationWindows(
      in: application,
      focusedWindow: focusedElement,
      fallbackWindow: window,
      timeout: Self.messagingTimeoutSeconds)
    guard isCurrentRequestedProcess(processID) else { return }
    let isTransientUnverifiedRead =
      evaluation.roleSnapshot.isUnavailable && evaluation.targetWindow == nil
    if isTransientUnverifiedRead, let cachedRoleSnapshot {
      publish(reason: reason, roleSnapshot: cachedRoleSnapshot)
      return
    }
    cachedRoleSnapshot = evaluation.roleSnapshot

    guard let target = evaluation.targetWindow else {
      if window != nil {
        identity &+= 1
        clearTrackedWindow()
      }
      publish(reason: reason, roleSnapshot: evaluation.roleSnapshot)
      return
    }

    let isNewWindow = window == nil || !CFEqual(window, target.element)
    if isNewWindow {
      clearTrackedWindow()
      window = target.element
      identity &+= 1
      if let observer {
        for name in windowNotifications {
          AXObserverAddNotification(
            observer, target.element, name as CFString, Unmanaged.passUnretained(self).toOpaque())
        }
      }
    }
    publish(
      reason: reason,
      focusedFrame: target.frame,
      roleSnapshot: evaluation.roleSnapshot)
  }

  static func isNonStructuralWindowNotification(_ reason: String) -> Bool {
    reason == kAXMovedNotification
      || reason == kAXResizedNotification
      || reason == kAXTitleChangedNotification
      || reason == kAXSelectedChildrenChangedNotification
  }

  private static func notificationPriority(for reason: String) -> Int {
    if isNonStructuralWindowNotification(reason) { return 0 }
    if reason == sampleReason { return 1 }
    if reason == kAXFocusedWindowChangedNotification || reason == kAXMainWindowChangedNotification {
      return 2
    }
    return 3
  }

  private var applicationNotifications: [String] {
    [
      kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification,
      kAXWindowCreatedNotification, kAXUIElementDestroyedNotification,
      kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
    ]
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

  private func publish(
    reason: String,
    focusedFrame: CGRect? = nil,
    roleSnapshot: AccessibilityWindowRoleSnapshot? = nil
  ) {
    deliver(
      WindowObservation(
        processID: processID,
        identity: identity,
        reason: reason,
        focusedFrame: focusedFrame,
        roleSnapshot: roleSnapshot))
  }

  static func roleSnapshot(for processID: pid_t) -> AccessibilityWindowRoleSnapshot? {
    dispatchPrecondition(condition: .notOnQueue(.main))
    guard AXIsProcessTrusted(), processID > 0 else { return nil }
    let app = AXUIElementCreateApplication(processID)
    AXUIElementSetMessagingTimeout(app, lookupMessagingTimeoutSeconds)
    let focused = copyWindowAttribute(
      kAXFocusedWindowAttribute, from: app, timeout: lookupMessagingTimeoutSeconds)
    return evaluateApplicationWindows(
      in: app,
      focusedWindow: focused,
      fallbackWindow: nil,
      timeout: lookupMessagingTimeoutSeconds
    ).roleSnapshot
  }

  private static func evaluateApplicationWindows(
    in application: AXUIElement,
    focusedWindow: AXUIElement?,
    fallbackWindow: AXUIElement?,
    timeout: Float
  ) -> (targetWindow: InspectedWindow?, roleSnapshot: AccessibilityWindowRoleSnapshot) {
    var snapshot = AccessibilityWindowRoleSnapshot()
    let windowList = copyWindows(from: application)
    var orderedElements = windowList.elements
    if let focusedWindow {
      orderedElements.removeAll { CFEqual($0, focusedWindow) }
      orderedElements.insert(focusedWindow, at: 0)
    }

    var inspectedWindows: [InspectedWindow] = []
    for element in orderedElements.prefix(maxInspectedWindowCount) {
      guard let inspected = inspectWindow(element, timeout: timeout) else {
        continue
      }
      inspectedWindows.append(inspected)
      if inspected.isStandardWindow {
        snapshot.standardWindowFrames.append(inspected.frame)
        if let focusedWindow, CFEqual(element, focusedWindow) {
          snapshot.focusedStandardWindowFrame = inspected.frame
        }
      } else if !inspected.frame.isEmpty {
        snapshot.nonStandardWindowFrames.append(inspected.frame)
      }
    }
    snapshot.hasVerifiedWindowList =
      windowList.succeeded && (orderedElements.isEmpty || !inspectedWindows.isEmpty)
    snapshot.hasExactStandardWindowFrames = snapshot.hasVerifiedWindowList

    var fallbackInspected: InspectedWindow?
    if let fallbackWindow,
      !inspectedWindows.contains(where: { CFEqual($0.element, fallbackWindow) }),
      let inspected = inspectWindow(fallbackWindow, timeout: timeout)
    {
      fallbackInspected = inspected
      if !inspected.isStandardWindow && !inspected.frame.isEmpty {
        snapshot.nonStandardWindowFrames.append(inspected.frame)
      }
    }

    let targetWindow = resolveStandardTargetWindow(
      focusedWindow: focusedWindow,
      fallbackWindow: fallbackWindow,
      fallbackInspected: fallbackInspected,
      inspectedWindows: inspectedWindows)
    return (targetWindow, snapshot)
  }

  private static func resolveStandardTargetWindow(
    focusedWindow: AXUIElement?,
    fallbackWindow: AXUIElement?,
    fallbackInspected: InspectedWindow?,
    inspectedWindows: [InspectedWindow]
  ) -> InspectedWindow? {
    if let focusedWindow,
      let matchedFocused = inspectedWindows.first(where: { CFEqual($0.element, focusedWindow) }),
      matchedFocused.isStandardWindow
    {
      return matchedFocused
    }
    if let fallbackWindow {
      if let matchedFallback = inspectedWindows.first(where: { CFEqual($0.element, fallbackWindow) }
      ) {
        if matchedFallback.isStandardWindow {
          return matchedFallback
        }
      } else if let fallbackInspected, fallbackInspected.isStandardWindow {
        return fallbackInspected
      }
    }
    return inspectedWindows.first(where: \.isStandardWindow)
  }

  private static func inspectWindow(
    _ window: AXUIElement,
    timeout: Float
  ) -> InspectedWindow? {
    AXUIElementSetMessagingTimeout(window, timeout)
    var rawValues: CFArray?
    guard
      AXUIElementCopyMultipleAttributeValues(
        window,
        AccessibilityWindowInspection.attributeKeys as CFArray,
        [],
        &rawValues) == .success,
      let values = rawValues as? [AnyObject],
      let inspection = AccessibilityWindowInspection(values: values)
    else { return nil }
    return InspectedWindow(
      element: window,
      frame: inspection.frame,
      isStandardWindow: inspection.isStandardWindow)
  }

  private static func copyWindowAttribute(
    _ attribute: String,
    from element: AXUIElement,
    timeout: Float
  ) -> AXUIElement? {
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
      let value, CFGetTypeID(value) == AXUIElementGetTypeID()
    else { return nil }
    let window = unsafeDowncast(value as AnyObject, to: AXUIElement.self)
    AXUIElementSetMessagingTimeout(window, timeout)
    return window
  }

  private static func copyWindows(
    from application: AXUIElement
  ) -> (elements: [AXUIElement], succeeded: Bool) {
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value)
        == .success,
      let elements = value as? [AXUIElement]
    else { return ([], false) }
    return (elements, true)
  }

  static func boundWindowInventory(for pid: pid_t) -> BoundWindows.Inventory? {
    dispatchPrecondition(condition: .notOnQueue(.main))
    guard AXIsProcessTrusted() else { return nil }
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, lookupMessagingTimeoutSeconds)
    let list = copyWindows(from: app)
    guard list.succeeded else { return nil }
    var hidden: CFTypeRef?
    let status = AXUIElementCopyAttributeValue(app, kAXHiddenAttribute as CFString, &hidden)
    let windows = list.elements.prefix(maxInspectedWindowCount).compactMap { element in
      inspectWindow(element, timeout: lookupMessagingTimeoutSeconds).map {
        BoundWindows.Inventory.Window(element: element, frame: $0.frame)
      }
    }
    return .init(
      windows: windows, isComplete: windows.count == list.elements.count,
      isApplicationHidden: status == .success ? hidden as? Bool : nil)
  }

}

extension AccessibilityWindowSource {
  /// Native gateway for recording-owned call workers. AX handles stay inside their actor.
  /// This gateway has no tracking state, observers or hierarchy-discovery scheduling.
  enum CallMetadata {
    static func values(_ attributes: [String], of element: AXUIElement) -> [AnyObject]? {
      dispatchPrecondition(condition: .notOnQueue(.main))
      var result: CFArray?
      guard
        AXUIElementCopyMultipleAttributeValues(element, attributes as CFArray, [], &result)
          == .success,
        let values = result as? [AnyObject], values.count == attributes.count
      else { return nil }
      return values
    }
    static func elements(_ attribute: String, of element: AXUIElement, limit: Int) -> [AXUIElement]?
    {
      dispatchPrecondition(condition: .notOnQueue(.main))
      var count: CFIndex = 0
      let status = AXUIElementGetAttributeValueCount(element, attribute as CFString, &count)
      // Leaf controls need not expose AXChildren. Failed IPC and required inventories stay unavailable.
      if attribute == kAXChildrenAttribute, status == .attributeUnsupported { return [] }
      guard status == .success, count >= 0, count <= limit else { return nil }
      if count == 0 { return [] }
      var result: CFArray?
      guard
        AXUIElementCopyAttributeValues(element, attribute as CFString, 0, count, &result)
          == .success,
        let values = result as? [AnyObject], values.count == count,
        values.allSatisfy({ CFGetTypeID($0) == AXUIElementGetTypeID() })
      else { return nil }
      return values.map { unsafeDowncast($0, to: AXUIElement.self) }
    }
    static func manualAccessibilityLease(processID: Int32) -> CallAccessibilityRegistry.Restoration
    {
      dispatchPrecondition(condition: .notOnQueue(.main))
      let application = AXUIElementCreateApplication(processID)
      AXUIElementSetMessagingTimeout(application, CallSpeakerAX.timeout)
      var previous: CFTypeRef?
      guard
        AXUIElementCopyAttributeValue(application, "AXManualAccessibility" as CFString, &previous)
          == .success,
        previous as? Bool == false,
        AXUIElementSetAttributeValue(
          application, "AXManualAccessibility" as CFString, kCFBooleanTrue) == .success
      else { return .init(restore: { true }) }
      return .init(restore: {
        dispatchPrecondition(condition: .notOnQueue(.main))
        return AXUIElementSetAttributeValue(
          application, "AXManualAccessibility" as CFString, kCFBooleanFalse) == .success
      })
    }
  }
}
