import AppKit
import SwiftUI

private struct SelectionCommandView: View {
  let model: SelectionCommandCoordinator
  let copy: (String) -> Void
  let history: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 9) {
        Image(systemName: "text.badge.star")
          .foregroundStyle(SilliesTheme.accent).frame(width: 28, height: 28)
          .background(SilliesTheme.accent.opacity(0.14), in: Circle())
        SessionHUDLabel(title: model.title, status: model.status)
        if model.isWorking {
          ProgressView().controlSize(.mini)
        } else {
          Button(action: history) {
            Image(systemName: "text.bubble").frame(width: 24, height: 24)
          }.buttonStyle(.plain).help("Review recent writing").accessibilityLabel(
            "Review recent writing")
        }
        if let result = model.result {
          SessionHUDAction(title: "Copy") { copy(result.text) }
        }
        SessionHUDDismiss(title: model.isWorking ? "Cancel writing" : "Dismiss") { model.dismiss() }
      }
      if let failure = model.insertionFailure { SessionFailureNotice(failure: failure) }
    }
    .padding(.horizontal, 11).padding(.vertical, 8)
    .frame(width: WritingFeedbackLayout.width)
    .background(SessionHUDBackground(emphasis: model.isWorking ? .active : .completed))
    .foregroundStyle(SilliesTheme.ink).tint(SilliesTheme.accent)
    .fixedSize(horizontal: false, vertical: true).padding(WritingFeedbackLayout.shadowInset)
  }
}

@MainActor final class SelectionCommandPanel {
  private let panel = AnchoredWritingPanel<SelectionCommandView>()
  func attach(to companion: WritingCompanionAnchor) { panel.attach(to: companion) }
  func prepare(
    _ model: SelectionCommandCoordinator, copy: @escaping (String) -> Void,
    history: @escaping () -> Void
  ) {
    panel.prepare(SelectionCommandView(model: model, copy: copy, history: history))
  }
  func show(
    _ model: SelectionCommandCoordinator, copy: @escaping (String) -> Void,
    history: @escaping () -> Void
  ) {
    guard model.isPresented else {
      panel.hide()
      return
    }
    panel.show(
      SelectionCommandView(model: model, copy: copy, history: history),
      sizing: model.insertionFailure.map { .notice($0.message) } ?? .compact)
  }
  func close() { panel.close() }
}
