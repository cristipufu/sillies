import AppKit
import SwiftUI

private struct SelectionCommandView: View {
  let model: SelectionCommandCoordinator
  let copy: (String) -> Void
  let close: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        if model.isWorking { ProgressView().controlSize(.small) }
        Text(model.status).font(.system(size: 13, weight: .semibold, design: .rounded))
        Spacer(minLength: 4)
        Button {
          model.cancel()
          close()
        } label: {
          Image(systemName: "xmark")
        }
        .accessibilityLabel(model.isWorking ? "Cancel writing" : "Dismiss")
      }
      if let result = model.result {
        Text(result.text).font(.callout).lineLimit(5)
        if !result.notice.isEmpty { Text(result.notice).font(.caption).foregroundStyle(.secondary) }
        Button("Copy edited text") { copy(result.text) }
      }
    }.padding(16).frame(width: WritingFeedbackLayout.width).fixedSize(
      horizontal: false, vertical: true
    )
    .background(
      SilliesTheme.card, in: RoundedRectangle(cornerRadius: WritingFeedbackLayout.cornerRadius)
    )
    .overlay(
      RoundedRectangle(cornerRadius: WritingFeedbackLayout.cornerRadius).strokeBorder(
        SilliesTheme.border)
    )
    .foregroundStyle(SilliesTheme.ink).padding(WritingFeedbackLayout.shadowInset)
  }
}

@MainActor final class SelectionCommandPanel {
  private let panel = AnchoredWritingPanel<SelectionCommandView>()
  func move(to point: CGPoint) { panel.move(to: point) }
  func prepare(_ model: SelectionCommandCoordinator, copy: @escaping (String) -> Void) {
    panel.prepare(
      SelectionCommandView(model: model, copy: copy, close: { [weak self] in self?.close() }))
  }
  func show(_ model: SelectionCommandCoordinator, copy: @escaping (String) -> Void) {
    panel.show(
      SelectionCommandView(model: model, copy: copy, close: { [weak self] in self?.close() }))
  }
  func close() { panel.close() }
}
