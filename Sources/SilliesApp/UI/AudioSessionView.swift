import SilliesCore
import SwiftUI

struct AudioSessionView: View {
  private enum Layout {
    static let padding: CGFloat = 24
    static let spacing: CGFloat = 18
    static let minimumWidth: CGFloat = 560
    static let minimumHeight: CGFloat = 640
  }
  let model: AudioSessionPresentation

  var body: some View {
    ViewThatFits(in: .vertical) {
      content
      ScrollView { content }
    }
    .frame(minWidth: Layout.minimumWidth, minHeight: Layout.minimumHeight)
    .background(SilliesTheme.paper).foregroundStyle(SilliesTheme.ink)
    .tint(SilliesTheme.accent)
    .onAppear { model.hasUnreadSuggestion = false }
    .onChange(of: model.suggestions.count) { _, _ in model.hasUnreadSuggestion = false }
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: Layout.spacing) {
      AudioSessionHeader(model: model)
      AudioLanguagePicker(model: model)
      if case .failed(let message) = model.phase {
        AudioSessionNotice(
          message: message, opensPrivacy: SessionRecord.indicatesPermissionNeeded(message))
      }
      if model.kind == .participate { AudioMeetingSuggestionsView(model: model) }
      AudioTranscriptView(model: model)
      footer
    }
    .padding(Layout.padding)
  }

  private var footer: some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: "lock.shield").foregroundStyle(SilliesTheme.accent)
      Text(
        model.isFinished
          ? "Saved on this Mac. Open the Vault for your transcript and notes."
          : model.isPaused
            ? "Paused audio isn’t saved or transcribed. Resume whenever you’re ready."
            : "Processed on this Mac. Closing this window keeps the session running; Finish & Save stops it."
      )
      .fixedSize(horizontal: false, vertical: true)
    }
    .font(.caption).foregroundStyle(SilliesTheme.secondary)
  }
}
