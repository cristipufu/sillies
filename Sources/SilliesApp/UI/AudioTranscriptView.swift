import SwiftUI

struct AudioTranscriptView: View {
  let model: AudioSessionPresentation

  var body: some View {
    @Bindable var session = model
    SessionTranscriptCard(
      text: model.transcript, isFinished: model.isFinished,
      followsLive: $session.followsLiveTranscript
    ) {
      VStack(spacing: 10) {
        Image(systemName: "waveform").font(.system(size: 28)).foregroundStyle(
          SilliesTheme.accent)
        Text(
          model.phase == .capturing
            ? "Ready for your words" : "Your transcript will appear here"
        )
        .font(.callout.weight(.medium))
        Text(
          model.displayedLanguage.map {
            "Speak in \($0.name). Speech may take a moment to appear."
          }
            ?? "Choose a ready language to begin."
        )
        .font(.caption).foregroundStyle(SilliesTheme.secondary)
      }.frame(maxWidth: .infinity).padding(.vertical, 32)
    }
  }
}
