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
    content
      .frame(minWidth: Layout.minimumWidth, minHeight: Layout.minimumHeight)
      .background(SilliesTheme.paper).foregroundStyle(SilliesTheme.ink)
      .tint(SilliesTheme.accent)
      .onAppear { model.hasUnreadSuggestion = false }
      .onChange(of: model.suggestions.count) { _, _ in model.hasUnreadSuggestion = false }
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: Layout.spacing) {
      AudioSessionHeader(model: model)
        .fixedSize(horizontal: false, vertical: true)
      // Only the controls participate in fitting. The native transcript keeps a stable viewport.
      ViewThatFits(in: .vertical) {
        options
        ScrollView { options }
          .scrollBounceBehavior(.basedOnSize)
      }
      AudioTranscriptView(model: model)
      footer
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(Layout.padding)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var options: some View {
    VStack(alignment: .leading, spacing: Layout.spacing) {
      AudioLanguagePicker(model: model)
      if model.diarizationModel != nil {
        Label(
          model.speakerDetectionNotice ?? "Speaker labels enabled · Labels may take a few seconds",
          systemImage: "person.2.wave.2"
        )
        .font(.caption).foregroundStyle(SilliesTheme.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }
      if case .failed(let failure) = model.phase {
        SessionFailureNotice(failure: failure)
      }
      if let failure = model.transcriptionFailure {
        SessionFailureNotice(failure: failure)
      }
      if model.kind == .participate { AudioMeetingSuggestionsView(model: model) }
    }
  }

  private var footer: some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: "lock.shield").foregroundStyle(SilliesTheme.accent)
      Text(footerMessage)
        .fixedSize(horizontal: false, vertical: true)
    }
    .font(.caption).foregroundStyle(SilliesTheme.secondary)
  }

  private var footerMessage: String {
    switch model.phase {
    case .finished: "Saved on this Mac. Open the Vault for your transcript and notes."
    case .paused: "Paused audio isn’t saved or transcribed. Resume whenever you’re ready."
    case .failed: "Choose Finish & Save to keep the available transcript and recording."
    default:
      "Processed on this Mac. Closing this window keeps the session running; Finish & Save stops it."
    }
  }
}
