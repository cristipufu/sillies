import AppKit
import QuartzCore
import SilliesCore

@MainActor
final class CompanionPanel: NSPanel {
  enum Stacking: Equatable {
    case following(windowLayer: Int)
    case bound(windowID: UInt32, windowLayer: Int)
    case pickedUp
  }
  private var stacking: Stacking = .following(windowLayer: 0)
  private var occlusionExclusion: WindowTrackingExclusions.Registration?
  private static let windowLevelOffsetAboveTarget = 1
  private static let hudLevelOffsetAboveCompanion = 1
  private static let defaultScreenVisibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
  static let normalOverlayLevel = NSWindow.Level(
    rawValue: NSWindow.Level.normal.rawValue + windowLevelOffsetAboveTarget)
  static let floatingOverlayLevel = NSWindow.Level(
    rawValue: NSWindow.Level.floating.rawValue + windowLevelOffsetAboveTarget)
  static let overlayLevel = floatingOverlayLevel
  static let transcriptionLevel = NSWindow.Level(
    rawValue: floatingOverlayLevel.rawValue + hudLevelOffsetAboveCompanion + 1)
  static let overlayCollectionBehavior: NSWindow.CollectionBehavior = [
    .canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .ignoresCycle, .transient,
  ]

  static var isRunningUnderUnitTests: Bool {
    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
      || ProcessInfo.processInfo.arguments.contains {
        $0.contains("swift-testing") || $0.hasSuffix(".xctest")
      }
  }

  static func visibleFrame(for preferredScreen: NSScreen? = nil) -> CGRect {
    (preferredScreen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
      ?? defaultScreenVisibleFrame
  }

  static func visibleFrame(containing point: CGPoint) -> CGRect {
    visibleFrame(for: NSScreen.screens.first { $0.frame.contains(point) })
  }

  static func overlayLevel(
    forWindowLayer windowLayer: Int,
    isPickedUp: Bool = false
  ) -> NSWindow.Level {
    if isPickedUp || windowLayer >= NSWindow.Level.floating.rawValue {
      return floatingOverlayLevel
    }
    return normalOverlayLevel
  }

  static func hudLevel(forWindowLayer windowLayer: Int) -> NSWindow.Level {
    let companionLevel = overlayLevel(forWindowLayer: windowLayer, isPickedUp: false)
    return NSWindow.Level(rawValue: companionLevel.rawValue + hudLevelOffsetAboveCompanion)
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
    frameRect
  }

  init(view: CompanionView) {
    super.init(
      contentRect: view.bounds, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: false)
    contentView = view
    view.autoresizingMask = []
    backgroundColor = .clear
    isOpaque = false
    hasShadow = false
    minSize = .zero
    level = Self.normalOverlayLevel
    hidesOnDeactivate = false
    isReleasedWhenClosed = false
    ignoresMouseEvents = true
    acceptsMouseMovedEvents = true
    collectionBehavior = Self.overlayCollectionBehavior
    animationBehavior = .none
    occlusionExclusion = WindowTrackingExclusions.transparentOverlays.register(UInt32(windowNumber))
    if Self.isRunningUnderUnitTests { alphaValue = 0 }
  }

  func updateStacking(_ stacking: Stacking) {
    guard self.stacking != stacking else { return }
    self.stacking = stacking
    let targetLevel: NSWindow.Level
    switch stacking {
    case .following(let layer): targetLevel = Self.overlayLevel(forWindowLayer: layer)
    case .bound(_, let layer): targetLevel = NSWindow.Level(rawValue: layer)
    case .pickedUp: targetLevel = Self.floatingOverlayLevel
    }
    if level != targetLevel {
      level = targetLevel
    }
    restoreAttachmentOrder()
  }

  func presentAtAttachment() {
    if case .bound(let id, _) = stacking {
      order(.above, relativeTo: Int(id))
    } else {
      orderFrontRegardless()
    }
  }

  func restoreAttachmentOrder() {
    guard isVisible, case .bound(let id, _) = stacking else { return }
    order(.above, relativeTo: Int(id))
  }
}
