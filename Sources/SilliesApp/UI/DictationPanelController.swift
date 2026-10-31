import AppKit
import SilliesWriting
import SwiftUI

struct DictationFeedbackView: View {
  let model: DictationCoordinator
  let openSession: () -> Void
  let copy: (String) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 9) {
        SessionAudioIndicator(level: model.level, isCapturing: model.phase == .listening)
        SessionHUDLabel(title: "Dictate · \(model.applicationName)", status: model.hudStatus)
        Button(action: openSession) {
          Image(systemName: "text.bubble").foregroundStyle(SilliesTheme.accent)
            .frame(width: 24, height: 24)
        }.buttonStyle(.plain).help("Open dictation and transcript")
          .accessibilityLabel("Open dictation session")
        if model.canFinish {
          SessionHUDAction(title: "Finish") { model.finish() }
        } else if let result = model.result {
          SessionHUDAction(title: "Copy") { copy(result.text) }
        } else if model.isActive {
          ProgressView().controlSize(.mini)
        }
        SessionHUDDismiss(title: model.isActive ? "Cancel dictation" : "Dismiss") {
          model.dismiss()
        }
      }
      if let failure = model.recoveryFailure { SessionFailureNotice(failure: failure) }
      if let failure = model.historyFailure {
        WritingHistoryNotice(failure: failure, retry: model.retryHistory)
      }
    }
    .padding(.horizontal, 11).padding(.vertical, 8)
    .frame(width: WritingFeedbackLayout.width)
    .background(SessionHUDBackground(emphasis: model.isActive ? .active : .completed))
    .foregroundStyle(SilliesTheme.ink).tint(SilliesTheme.accent)
    .fixedSize(horizontal: false, vertical: true).padding(WritingFeedbackLayout.shadowInset)
  }
}

@MainActor final class DictationPanelController {
  private let panel = AnchoredWritingPanel<DictationFeedbackView>()
  private let session = DictationSessionWindowController()
  private var companionName = "Your companion"
  var frame: CGRect? { panel.frame }
  var layoutMeasurements: Int { panel.layoutMeasurements }

  func prepare(
    _ model: DictationCoordinator, copy: @escaping (String) -> Void, history: @escaping () -> Void
  ) {
    panel.prepare(content(model, copy: copy, history: history))
  }
  func show(
    _ model: DictationCoordinator, copy: @escaping (String) -> Void, history: @escaping () -> Void
  ) {
    if model.phase == .idle {
      panel.hide()
      session.close()
      return
    }
    panel.show(
      content(model, copy: copy, history: history),
      sizing: .init(notices: [model.recoveryFailure?.message, model.historyFailure?.message]))
  }
  private func content(
    _ model: DictationCoordinator, copy: @escaping (String) -> Void, history: @escaping () -> Void
  ) -> DictationFeedbackView {
    DictationFeedbackView(
      model: model,
      openSession: { [weak self] in
        guard let self else { return }
        self.openSession(model, copy: copy, history: history)
      }, copy: copy)
  }
  func openSession(
    _ model: DictationCoordinator, copy: @escaping (String) -> Void, history: @escaping () -> Void
  ) {
    session.show(model, companionName: companionName, copy: copy, history: history)
  }
  func attach(to companion: WritingCompanionAnchor) {
    companionName = companion.name
    panel.attach(to: companion)
  }
  func close() {
    panel.close()
    session.close()
  }
}
