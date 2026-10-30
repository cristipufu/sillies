import AppKit

/// Compact decorative panels share input isolation, window ordering, and exclusion lifetime.
@MainActor
final class PlayfulPropPanel: NSPanel {
  static let geometryTolerance = 0.001
  private var registration: WindowTrackingExclusions.Registration?
  private var appliedFrame: CGRect?
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
  var preview: (NSView, CGRect)? {
    guard isVisible, let contentView else { return nil }
    return (contentView, frame)
  }

  init() {
    super.init(
      contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: false)
    isReleasedWhenClosed = false
    backgroundColor = .clear
    isOpaque = false
    hasShadow = false
    titlebarSeparatorStyle = .none
    ignoresMouseEvents = true
    hidesOnDeactivate = false
    animationBehavior = .none
    collectionBehavior = CompanionPanel.overlayCollectionBehavior
    prepare()
    if CompanionPanel.isRunningUnderUnitTests { alphaValue = 0 }
  }

  func prepare() {
    if registration == nil {
      registration = WindowTrackingExclusions.transparentOverlays.register(UInt32(windowNumber))
    }
  }

  func present(frame: CGRect, level: NSWindow.Level) {
    prepare()
    let previous = appliedFrame
    appliedFrame = frame
    if previous == nil || abs((previous?.width ?? 0) - frame.width) > Self.geometryTolerance
      || abs((previous?.height ?? 0) - frame.height) > Self.geometryTolerance
    {
      setFrame(frame, display: false)
    } else if previous?.origin != frame.origin {
      setFrameOrigin(frame.origin)
    }
    if self.level != level { self.level = level }
    if !isVisible { orderFrontRegardless() }
  }

  func hide() { if isVisible { orderOut(nil) } }

  override func close() {
    hide()
    super.close()
    registration = nil
    appliedFrame = nil
  }
}
