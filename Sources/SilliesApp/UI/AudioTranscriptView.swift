import SwiftUI

struct AudioTranscriptView: View {
  @Environment(\.silliesTheme) private var theme
  let model: AudioSessionPresentation

  var body: some View {
    @Bindable var session = model
    SessionTranscriptCard(
      text: model.transcript, isFinished: model.isFinished,
      followsLive: $session.followsLiveTranscript
    ) {
      VStack(spacing: 10) {
        Image(systemName: "waveform").font(.system(size: 28)).foregroundStyle(
          theme.accent)
        Text(
          model.phase == .capturing
            ? String(localized: "Ready for your words")
            : String(localized: "Your transcript will appear here")
        )
        .font(.callout.weight(.medium))
        Text(
          model.displayedLanguage.map {
            "Speak in \($0.name). Speech may take a moment to appear."
          }
            ?? String(localized: "Choose a ready language to begin.")
        )
        .font(.caption).foregroundStyle(theme.secondary)
      }.frame(maxWidth: .infinity).padding(.vertical, 32)
    }
  }
}
