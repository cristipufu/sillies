import AppKit

/// An app tool can take keyboard focus without becoming a companion perch or a skill target.
@MainActor
final class CompanionUtilityWindow: NSWindow {
  // Retain the exclusion while the window exists, including after close: metadata already
  // in flight must not turn this app-owned window into a perch. Registration releases on deinit.
  private var exclusion: WindowTrackingExclusions.Registration?
  override var canBecomeMain: Bool { false }
  override var canBecomeKey: Bool { true }

  override init(
    contentRect: NSRect, styleMask: NSWindow.StyleMask,
    backing: NSWindow.BackingStoreType, defer flag: Bool
  ) {
    super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
    level = CompanionPanel.contentWindowLevel
    registerExclusion()
  }

  override func makeKeyAndOrderFront(_ sender: Any?) {
    registerExclusion()
    super.makeKeyAndOrderFront(sender)
    registerExclusion()
  }

  private func registerExclusion() {
    guard let id = windowServerID else { return }
    guard exclusion?.windowID != id else { return }
    exclusion = nil
    exclusion = WindowTrackingExclusions.shared.register(id)
  }
}
