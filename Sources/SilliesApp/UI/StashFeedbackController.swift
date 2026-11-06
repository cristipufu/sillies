import AppKit
import SwiftUI

@MainActor @Observable
private final class StashFeedbackModel {
  var message = String(localized: "Drop to save")
  var recordID: UUID?
  var open: ((UUID) -> Void)?
  var undo: ((UUID) -> Void)?
  var dismiss: (() -> Void)?
}

private struct StashFeedbackView: View {
  @Environment(\.silliesTheme) private var theme
  let model: StashFeedbackModel
  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "tray.and.arrow.down.fill").foregroundStyle(theme.accent)
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
    .background(theme.card, in: RoundedRectangle(cornerRadius: 13))
    .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(theme.border))
    .foregroundStyle(theme.ink).padding(8)
  }
}

@MainActor
final class StashFeedbackController {
  struct Placement {
    let position: CGPoint
    var companion: CompanionWindowAnchor? = nil
  }
  private let appearance: ThemeEnvironment
  init(appearance: ThemeEnvironment) {
    self.appearance = appearance
  }

  private enum Presentation { case hint, actionable }
  private static let verticalOffset: CGFloat = 100
  private static let size = CGSize(width: 350, height: 64)
  private let model = StashFeedbackModel()
  private var panel: SkillFloatingPanel?

  func showDropTarget(at placement: Placement) {
    model.recordID = nil
    show(String(localized: "Drop to save"), at: placement, presentation: .hint)
  }

  func showSaved(
    _ id: UUID, at placement: Placement, open: @escaping (UUID) -> Void,
    undo: @escaping (UUID) -> Void
  ) {
    model.recordID = id
    model.open = open
    model.undo = { [weak self] in
      undo($0)
      self?.hide()
    }
    show(String(localized: "Saved"), at: placement, presentation: .actionable)
  }

  func showMessage(_ message: String, at placement: Placement) {
    model.recordID = nil
    show(message, at: placement, presentation: .actionable)
  }

  private func show(_ message: String, at placement: Placement, presentation: Presentation) {
    model.message = message
    model.dismiss = { [weak self] in self?.hide() }
    if panel == nil {
      let panel = SkillFloatingPanel(
        contentRect: CGRect(origin: .zero, size: Self.size), ignoresMouseEvents: false,
        level: .normal)
      let host = ThemedHostingView(
        rootView: StashFeedbackView(model: model), appearance: appearance)
      host.sizingOptions = []
      panel.contentView = host
      self.panel = panel
    }
    guard let panel else { return }
    panel.ignoresMouseEvents = presentation == .hint
    panel.level = placement.companion?.level ?? .normal
    let point = placement.position
    let screen = NSScreen.screens.first { $0.frame.contains(point) }
    let visible = CompanionPanel.visibleFrame(for: screen)
    let origin = CGPoint(
      x: min(max(point.x - Self.size.width / 2, visible.minX), visible.maxX - Self.size.width),
      y: min(max(point.y + Self.verticalOffset, visible.minY), visible.maxY - Self.size.height))
    panel.setFrameOrigin(origin)
    if let anchor = placement.companion {
      anchor.orderAbove(panel)
    } else {
      panel.orderFrontRegardless()
    }
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
