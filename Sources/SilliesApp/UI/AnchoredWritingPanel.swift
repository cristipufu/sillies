import AppKit
import SwiftUI

enum WritingFeedbackLayout {
  static let width: CGFloat = 420
  static let shadowInset: CGFloat = 14
  static let headTopOffsetFactor = 0.78
}

/// Shared non-activating presentation, measured from its contents and clamped to the visible screen.
@MainActor final class AnchoredWritingPanel<Content: View> {
  enum Sizing: Equatable {
    case compact
    case notice(String)
  }
  private var panel: SkillFloatingPanel?
  private var host: NSHostingController<Content>?
  private var anchor: WritingCompanionAnchor?
  private var measuredSizing: Sizing?
  private(set) var layoutMeasurements = 0
  var frame: CGRect? { panel?.frame }

  func prepare(_ content: Content) {
    guard panel == nil else { return }
    let panel = SkillFloatingPanel(contentRect: .zero, ignoresMouseEvents: false)
    let host = NSHostingController(rootView: content)
    host.sizingOptions = []
    panel.contentViewController = host
    self.panel = panel
    self.host = host
  }
  func show(_ content: Content, sizing: Sizing = .compact) {
    prepare(content)
    guard let panel, let host, let anchor else { return }
    if measuredSizing != sizing {
      host.rootView = content
      host.view.layoutSubtreeIfNeeded()
      let proposal = CGSize(
        width: WritingFeedbackLayout.width + 2 * WritingFeedbackLayout.shadowInset,
        height: CGFloat.greatestFiniteMagnitude)
      panel.setContentSize(host.sizeThatFits(in: proposal))
      measuredSizing = sizing
      layoutMeasurements += 1
    }
    attach(to: anchor)
    if !panel.isVisible { panel.order(.above, relativeTo: anchor.windowNumber) }
  }
  func attach(to companion: WritingCompanionAnchor) {
    anchor = companion
    let point = companion.position
    guard let panel else { return }
    let level = CompanionPanel.hudLevel(forWindowLayer: companion.windowLayer)
    if panel.level != level { panel.level = level }
    let visible = CompanionPanel.visibleFrame(
      for: NSScreen.screens.first { $0.frame.contains(point) })
    let size = panel.frame.size
    let origin = CGPoint(
      x: min(max(point.x - size.width / 2, visible.minX), visible.maxX - size.width),
      y: min(
        max(
          point.y + companion.characterSize * WritingFeedbackLayout.headTopOffsetFactor,
          visible.minY),
        visible.maxY - size.height))
    if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
  }
  func hide() { panel?.orderOut(nil) }
  func close() {
    panel?.close()
    panel = nil
    host = nil
    measuredSizing = nil
    anchor = nil
  }
}
