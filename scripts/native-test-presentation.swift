import AppKit
import Darwin
import ObjectiveC

/// Test-host-only interception. Reject presentation before it reaches WindowServer; never
/// pretend an ordering operation succeeded, since that would hide native UI regressions.
@MainActor enum NativeTestPresentation {
  static let rejectedPresentation: Int32 = 86

  static func configure() {
    if ProcessInfo.processInfo.environment["SILLIES_TEST_PRESENTATION"] == "gui" {
      NSApplication.shared.setActivationPolicy(.accessory)
      return
    }
    NSApplication.shared.setActivationPolicy(.prohibited)
    for name in ["orderFront:", "orderBack:", "makeKeyAndOrderFront:"] {
      let block: @convention(block) (NSWindow, AnyObject?) -> Void = { _, _ in reject(name) }
      replace(NSWindow.self, name, with: imp_implementationWithBlock(block))
    }
    for name in ["orderFrontRegardless", "makeKeyWindow", "makeMainWindow"] {
      let block: @convention(block) (NSWindow) -> Void = { _ in reject(name) }
      replace(NSWindow.self, name, with: imp_implementationWithBlock(block))
    }
    let selector = NSSelectorFromString("orderWindow:relativeTo:")
    guard let method = class_getInstanceMethod(NSWindow.self, selector) else {
      reject("Missing window-ordering boundary")
    }
    typealias Ordering = @convention(c) (NSWindow, Selector, Int, Int) -> Void
    let original = unsafeBitCast(method_getImplementation(method), to: Ordering.self)
    let ordering: @convention(block) (NSWindow, Int, Int) -> Void = { window, mode, relative in
      guard mode == NSWindow.OrderingMode.out.rawValue else { reject("orderWindow:relativeTo:") }
      original(window, selector, mode, relative)
    }
    method_setImplementation(method, imp_implementationWithBlock(ordering))
    let activate: @convention(block) (NSApplication, Bool) -> Void = { _, _ in
      reject("activateIgnoringOtherApps:")
    }
    replace(
      NSApplication.self, "activateIgnoringOtherApps:", with: imp_implementationWithBlock(activate))
    let activateCurrent: @convention(block) (NSApplication) -> Void = { _ in reject("activate") }
    replace(NSApplication.self, "activate", with: imp_implementationWithBlock(activateCurrent))
  }

  static func probe(_ operation: String) -> Never {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 80, height: 80), styleMask: [.borderless],
      backing: .buffered, defer: false)
    switch operation {
    case "front": window.orderFront(nil)
    case "back": window.orderBack(nil)
    case "key": window.makeKeyAndOrderFront(nil)
    case "regardless": window.orderFrontRegardless()
    case "relative": window.order(.above, relativeTo: 0)
    case "activate": NSApplication.shared.activate(ignoringOtherApps: true)
    case "activateCurrent": NSApplication.shared.activate()
    case "makeKey": window.makeKey()
    case "makeMain": window.makeMain()
    case "offscreen":
      window.contentView?.layoutSubtreeIfNeeded()
      window.orderOut(nil)
      window.close()
      exit(EXIT_SUCCESS)
    default: reject("Unknown presentation probe")
    }
    exit(EXIT_FAILURE)
  }

  private static func replace(_ type: AnyClass, _ name: String, with implementation: IMP) {
    guard let method = class_getInstanceMethod(type, NSSelectorFromString(name)) else {
      reject("Missing \(name) boundary")
    }
    method_setImplementation(method, implementation)
  }

  private static func reject(_ operation: String) -> Never {
    fputs(
      "Headless test rejected visible UI: \(operation). Classify the test as gui in execution-modes.json and run it explicitly with make gui-check.\n",
      stderr)
    exit(rejectedPresentation)
  }
}
