import AppKit
import Carbon
import SwiftUI
import Testing

@testable import SilliesApp

@Test @MainActor func controlCenterDismissesOutsideClicksWithoutSwallowingThemAndStopsMonitoring()
  throws
{
  _ = NSApplication.shared
  let anchor = NSWindow(
    contentRect: .init(x: 250, y: 250, width: 300, height: 200),
    styleMask: [.titled], backing: .buffered, defer: false)
  let other = NSWindow(
    contentRect: .init(x: 600, y: 250, width: 300, height: 200),
    styleMask: [.titled], backing: .buffered, defer: false)
  anchor.isReleasedWhenClosed = false
  other.isReleasedWhenClosed = false
  anchor.orderFrontRegardless()
  other.orderFrontRegardless()
  defer {
    anchor.close()
    other.close()
  }
  let button = NSButton(frame: .init(x: 10, y: 10, width: 30, height: 30))
  anchor.contentView?.addSubview(button)
  let popover = NSPopover()
  popover.animates = false
  popover.behavior = .applicationDefined
  popover.contentViewController = NSHostingController(
    rootView: Text("Crew").frame(width: 200, height: 150))
  let monitor = ControlCenterDismissal()
  defer {
    monitor.stop()
    popover.close()
  }
  popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
  monitor.start(popover: popover, statusButton: button)
  #expect(popover.isShown && monitor.isMonitoring)
  let buttonClick = try #require(
    NSEvent.mouseEvent(
      with: .leftMouseDown, location: .init(x: 20, y: 20), modifierFlags: [], timestamp: 0,
      windowNumber: anchor.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
  #expect(monitor.handleLocalEvent(buttonClick) === buttonClick)
  #expect(popover.isShown)
  let outside = try #require(
    NSEvent.mouseEvent(
      with: .leftMouseDown, location: .init(x: 20, y: 20), modifierFlags: [], timestamp: 0,
      windowNumber: other.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
  #expect(monitor.handleLocalEvent(outside) === outside)
  #expect(!popover.isShown && !monitor.isMonitoring)
  popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
  monitor.start(popover: popover, statusButton: button)
  let escape = try #require(
    NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
      windowNumber: popover.contentViewController?.view.window?.windowNumber ?? 0,
      context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false,
      keyCode: UInt16(kVK_Escape)))
  #expect(monitor.handleLocalEvent(escape) == nil)
  #expect(!popover.isShown && !monitor.isMonitoring)
}
