import AppKit
import SwiftUI

struct DictationFeedbackView: View {
  let model: DictationCoordinator
  let copy: (String) -> Void
  let history: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: model.isActive ? "waveform" : "text.bubble")
          .foregroundStyle(SilliesTheme.accent)
        Text(model.status).font(.system(size: 13, weight: .semibold, design: .rounded))
        Spacer(minLength: 0)
        Button {
          model.dismiss()
        } label: {
          Image(systemName: "xmark")
        }
        .accessibilityLabel(model.isActive ? "Cancel dictation" : "Dismiss")
      }
      if model.phase == .listening {
        ProgressView(value: min(1, model.level * 5)).tint(SilliesTheme.accent)
          .accessibilityLabel("Microphone level")
      }
      if !model.preview.isEmpty {
        Text(model.preview).font(.system(size: 12)).lineLimit(4)
          .foregroundStyle(SilliesTheme.secondary).frame(maxWidth: .infinity, alignment: .leading)
      }
      if let result = model.result, !result.notice.isEmpty {
        Text(result.notice).font(.caption).foregroundStyle(SilliesTheme.secondary)
      }
      HStack(spacing: 14) {
        if model.canFinish { Button("Finish") { model.finish() } }
        if model.isActive { Button("Cancel") { model.cancel() } }
        if let result = model.result { Button("Copy text") { copy(result.text) } }
        if !model.isActive { Button("Recovery history") { history() } }
      }.font(.system(size: 12, weight: .medium))
    }
    .buttonStyle(.plain).padding(16).frame(width: WritingFeedbackLayout.width)
    .background(
      SilliesTheme.card, in: RoundedRectangle(cornerRadius: WritingFeedbackLayout.cornerRadius)
    )
    .overlay(
      RoundedRectangle(cornerRadius: WritingFeedbackLayout.cornerRadius).strokeBorder(
        SilliesTheme.border)
    )
    .foregroundStyle(SilliesTheme.ink).fixedSize(horizontal: false, vertical: true).padding(
      WritingFeedbackLayout.shadowInset)
  }
}

@MainActor final class DictationPanelController {
  private let panel = AnchoredWritingPanel<DictationFeedbackView>()
  var frame: CGRect? { panel.frame }

  func prepare(
    _ model: DictationCoordinator, copy: @escaping (String) -> Void, history: @escaping () -> Void
  ) {
    panel.prepare(DictationFeedbackView(model: model, copy: copy, history: history))
  }
  func show(
    _ model: DictationCoordinator, copy: @escaping (String) -> Void, history: @escaping () -> Void
  ) {
    if model.phase == .idle {
      panel.hide()
      return
    }
    panel.show(DictationFeedbackView(model: model, copy: copy, history: history))
  }
  func move(to point: CGPoint) { panel.move(to: point) }
  func close() { panel.close() }
}
