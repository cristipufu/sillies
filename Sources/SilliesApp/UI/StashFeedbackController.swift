import AppKit
import SwiftUI

@MainActor @Observable
private final class StashFeedbackModel {
  var message = "Drop to save"
  var recordID: UUID?
  var open: ((UUID) -> Void)?
  var undo: ((UUID) -> Void)?
  var dismiss: (() -> Void)?
}

private struct StashFeedbackView: View {
  let model: StashFeedbackModel
  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "tray.and.arrow.down.fill").foregroundStyle(SilliesTheme.accent)
      Text(model.message).font(.system(size: 11, weight: .semibold, design: .rounded)).lineLimit(1)
      if let id = model.recordID {
        Button("View") { model.open?(id) }
        Button("Undo") { model.undo?(id) }
      }
      Button {
        model.dismiss?()
      } label: {
        Image(systemName: "xmark").font(.caption2)
      }
      .accessibilityLabel("Dismiss")
    }
    .buttonStyle(.plain).padding(12)
    .background(SilliesTheme.card, in: RoundedRectangle(cornerRadius: 13))
    .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(SilliesTheme.border))
    .foregroundStyle(SilliesTheme.ink).padding(8)
  }
}

@MainActor
final class StashFeedbackController {
  private enum Presentation { case hint, actionable }
  private static let verticalOffset: CGFloat = 100
  private static let size = CGSize(width: 350, height: 64)
  private let model = StashFeedbackModel()
  private var panel: SkillFloatingPanel?

  func showDropTarget(at point: CGPoint) {
    model.recordID = nil
    show("Drop to save", at: point, presentation: .hint)
  }

  func showSaved(
    _ id: UUID, at point: CGPoint, open: @escaping (UUID) -> Void, undo: @escaping (UUID) -> Void
  ) {
    model.recordID = id
    model.open = open
    model.undo = { [weak self] in
      undo($0)
      self?.hide()
    }
    show("Saved", at: point, presentation: .actionable)
  }

  func showMessage(_ message: String, at point: CGPoint) {
    model.recordID = nil
    show(message, at: point, presentation: .actionable)
  }

  private func show(_ message: String, at point: CGPoint, presentation: Presentation) {
    model.message = message
    model.dismiss = { [weak self] in self?.hide() }
    if panel == nil {
      let panel = SkillFloatingPanel(
        contentRect: CGRect(origin: .zero, size: Self.size), ignoresMouseEvents: false)
      let host = NSHostingView(rootView: StashFeedbackView(model: model))
      host.sizingOptions = []
      panel.contentView = host
      self.panel = panel
    }
    panel?.ignoresMouseEvents = presentation == .hint
    let screen = NSScreen.screens.first { $0.frame.contains(point) }
    let visible = CompanionPanel.visibleFrame(for: screen)
    let origin = CGPoint(
      x: min(max(point.x - Self.size.width / 2, visible.minX), visible.maxX - Self.size.width),
      y: min(max(point.y + Self.verticalOffset, visible.minY), visible.maxY - Self.size.height))
    panel?.setFrameOrigin(origin)
    panel?.orderFrontRegardless()
  }

  func hideDropTarget() { if model.recordID == nil { hide() } }
  func hide() { panel?.orderOut(nil) }
  func close() {
    panel?.close()
    panel = nil
    model.open = nil
    model.undo = nil
  }
}
