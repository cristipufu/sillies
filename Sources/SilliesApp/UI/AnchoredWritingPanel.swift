import AppKit
import SwiftUI

enum WritingFeedbackLayout {
  static let width: CGFloat = 350
  static let cornerRadius: CGFloat = 16
  static let shadowInset: CGFloat = 8
  static let perchGap: CGFloat = 45
}

/// Shared non-activating presentation, measured from its contents and clamped to the visible screen.
@MainActor final class AnchoredWritingPanel<Content: View> {
  private var panel: SkillFloatingPanel?
  private var host: NSHostingController<Content>?
  private var anchor = CGPoint.zero
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
  func show(_ content: Content) {
    prepare(content)
    guard let panel, let host else { return }
    host.rootView = content
    host.view.layoutSubtreeIfNeeded()
    let proposal = CGSize(
      width: WritingFeedbackLayout.width + 2 * WritingFeedbackLayout.shadowInset,
      height: CGFloat.greatestFiniteMagnitude)
    panel.setContentSize(host.sizeThatFits(in: proposal))
    move(to: anchor)
    panel.orderFrontRegardless()
  }
  func move(to point: CGPoint) {
    anchor = point
    guard let panel else { return }
    let visible = CompanionPanel.visibleFrame(
      for: NSScreen.screens.first { $0.frame.contains(point) })
    let size = panel.frame.size
    panel.setFrameOrigin(
      .init(
        x: min(max(point.x - size.width / 2, visible.minX), visible.maxX - size.width),
        y: min(
          max(point.y + WritingFeedbackLayout.perchGap, visible.minY), visible.maxY - size.height)))
  }
  func hide() { panel?.orderOut(nil) }
  func close() {
    panel?.close()
    panel = nil
    host = nil
  }
}
