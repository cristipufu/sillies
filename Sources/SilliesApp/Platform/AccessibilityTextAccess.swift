import ApplicationServices
import Foundation

struct TextDestination: Sendable {
  let id: UUID
  let processID: Int32
  let applicationName: String
  let bundleIdentifier: String?
  let selection: String
}

enum TextAccessError: LocalizedError {
  case permission, unsupported, protectedField, changed, failed, clipboardRestore
  var errorDescription: String? {
    switch self {
    case .permission: "Enable Accessibility to insert text. Your result can still be copied."
    case .unsupported: "This field does not support safe insertion. Copy the result instead."
    case .protectedField: "Dictation is unavailable in a protected field."
    case .changed: "The destination changed. Your text is ready to copy or paste."
    case .failed: "Insertion could not be confirmed. Check the field before pasting again."
    case .clipboardRestore:
      "Text may already be inserted, but the previous clipboard could not be restored. Check the field before pasting again."
    }
  }
}

/// Explicit selection and insertion only. AX objects remain on this isolated worker.
actor AccessibilityTextAccess: TextDestinationAccess {
  private struct WindowIdentity {
    let element: AXUIElement
    let title: String?
    let document: String?
    func matches(_ other: WindowIdentity) -> Bool {
      CFEqual(element, other.element) && title == other.title && document == other.document
    }
  }
  private struct Focus {
    let destination: TextDestination
    let element: AXUIElement
    let range: CFRange
    let contextRange: CFRange
    let context: String
    let window: WindowIdentity
  }
  private enum Limits {
    static let timeout: Float = 0.08
    static let contextLength = 64
    static let maximumSelectionLength = 16_000
  }
  private var focus: Focus?

  func capture(_ application: FrontmostApplication) throws -> TextDestination {
    dispatchPrecondition(condition: .notOnQueue(.main))
    focus = nil
    // In-process AX setters bypass IPC and can invoke AppKit directly on this worker.
    guard application.processID != ProcessInfo.processInfo.processIdentifier else {
      throw TextAccessError.unsupported
    }
    guard AXIsProcessTrusted() else { throw TextAccessError.permission }
    let element = try focusedElement(processID: application.processID)
    if string(kAXSubroleAttribute, from: element) == kAXSecureTextFieldSubrole {
      throw TextAccessError.protectedField
    }
    guard let range = selectionRange(element), range.location >= 0,
      range.length >= 0, range.length <= Limits.maximumSelectionLength
    else { throw TextAccessError.unsupported }
    let selected = string(kAXSelectedTextAttribute, from: element) ?? ""
    guard range.length == selected.utf16.count else { throw TextAccessError.unsupported }
    let contextRange = CFRange(
      location: max(0, range.location - Limits.contextLength),
      length: min(range.location, Limits.contextLength))
    let context = try substring(element, range: contextRange)
    let destination = TextDestination(
      id: UUID(), processID: application.processID,
      applicationName: application.name, bundleIdentifier: application.bundleIdentifier,
      selection: selected)
    focus = Focus(
      destination: destination, element: element, range: range,
      contextRange: contextRange, context: context, window: try windowIdentity(element))
    return destination
  }

  func insert(_ text: String, into destination: TextDestination) throws -> NativeTextInsertion {
    dispatchPrecondition(condition: .notOnQueue(.main))
    try Task.checkCancellation()
    let current = try validated(destination)
    if text.contains(where: \.isNewline),
      Self.terminalApplications.contains(destination.bundleIdentifier ?? "")
    {
      throw TextAccessError.unsupported
    }
    var settable = DarwinBoolean(false)
    guard
      AXUIElementIsAttributeSettable(
        current.element, kAXSelectedTextAttribute as CFString,
        &settable) == .success, settable.boolValue
    else { return .requiresClipboard }
    guard
      AXUIElementSetAttributeValue(
        current.element, kAXSelectedTextAttribute as CFString,
        text as CFString) == .success
    else { throw TextAccessError.failed }
    focus = nil
    return .inserted
  }

  private static let terminalApplications: Set<String> = [
    "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
    "net.kovidgoyal.kitty", "org.alacritty", "co.zeit.hyper", "com.github.wez.wezterm",
  ]

  func validate(_ destination: TextDestination) throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    try Task.checkCancellation()
    _ = try validated(destination)
  }

  func confirms(_ text: String, at destination: TextDestination) -> Bool {
    guard let focus, focus.destination.id == destination.id else { return false }
    do {
      return try substring(
        focus.element,
        range: CFRange(location: focus.range.location, length: text.utf16.count)) == text
    } catch { return false }
  }

  func release(_ destination: TextDestination) {
    if focus?.destination.id == destination.id { focus = nil }
  }

  private func validated(_ destination: TextDestination) throws -> Focus {
    guard let focus, focus.destination.id == destination.id,
      CFEqual(try focusedElement(processID: destination.processID), focus.element),
      focus.window.matches(try windowIdentity(focus.element)),
      let range = selectionRange(focus.element),
      range.location == focus.range.location, range.length == focus.range.length,
      (string(kAXSelectedTextAttribute, from: focus.element) ?? "") == destination.selection,
      try substring(focus.element, range: focus.contextRange) == focus.context
    else { throw TextAccessError.changed }
    return focus
  }

  private func windowIdentity(_ field: AXUIElement) throws -> WindowIdentity {
    guard let window = element(kAXWindowAttribute, from: field) else {
      throw TextAccessError.unsupported
    }
    AXUIElementSetMessagingTimeout(window, Limits.timeout)
    enum Attribute: Int, CaseIterable {
      case title, document
      var key: String { self == .title ? kAXTitleAttribute : kAXDocumentAttribute }
    }
    var values: CFArray?
    guard
      AXUIElementCopyMultipleAttributeValues(
        window, Attribute.allCases.map(\.key) as CFArray, [], &values) == .success,
      let values = values as? [Any], values.count == Attribute.allCases.count
    else { throw TextAccessError.unsupported }
    return WindowIdentity(
      element: window, title: values[Attribute.title.rawValue] as? String,
      document: values[Attribute.document.rawValue] as? String)
  }

  private func focusedElement(processID: Int32) throws -> AXUIElement {
    let system = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(system, Limits.timeout)
    guard let app = element(kAXFocusedApplicationAttribute, from: system) else {
      throw TextAccessError.unsupported
    }
    var pid: pid_t = 0
    guard AXUIElementGetPid(app, &pid) == .success, pid == processID else {
      throw TextAccessError.changed
    }
    AXUIElementSetMessagingTimeout(app, Limits.timeout)
    guard let field = element(kAXFocusedUIElementAttribute, from: app) else {
      throw TextAccessError.unsupported
    }
    AXUIElementSetMessagingTimeout(field, Limits.timeout)
    return field
  }

  private func element(_ key: String, from parent: AXUIElement) -> AXUIElement? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(parent, key as CFString, &value) == .success,
      let value, CFGetTypeID(value) == AXUIElementGetTypeID()
    else { return nil }
    return unsafeDowncast(value as AnyObject, to: AXUIElement.self)
  }

  private func string(_ key: String, from element: AXUIElement) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else {
      return nil
    }
    return value as? String
  }

  private func selectionRange(_ element: AXUIElement) -> CFRange? {
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value)
        == .success,
      let value, CFGetTypeID(value) == AXValueGetTypeID()
    else { return nil }
    var range = CFRange()
    guard AXValueGetValue(unsafeDowncast(value as AnyObject, to: AXValue.self), .cfRange, &range)
    else { return nil }
    return range
  }

  private func substring(_ element: AXUIElement, range: CFRange) throws -> String {
    if range.length == 0 { return "" }
    var range = range
    guard let parameter = AXValueCreate(.cfRange, &range) else { throw TextAccessError.unsupported }
    var value: CFTypeRef?
    guard
      AXUIElementCopyParameterizedAttributeValue(
        element, kAXStringForRangeParameterizedAttribute as CFString,
        parameter, &value) == .success, let text = value as? String
    else { throw TextAccessError.unsupported }
    return text
  }
}
