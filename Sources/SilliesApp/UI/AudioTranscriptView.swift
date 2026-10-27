import SwiftUI

struct AudioTranscriptView: View {
  private static let endAnchor = "transcript-end"
  private static let minimumTranscriptHeight: CGFloat = 160
  let model: AudioSessionPresentation

  var body: some View {
    @Bindable var session = model
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(model.isFinished ? "Transcript" : "Live transcript").font(.headline)
        Spacer()
        if !model.isFinished, !model.transcript.isEmpty {
          Toggle("Follow live", isOn: $session.followsLiveTranscript).toggleStyle(.checkbox)
            .font(.caption).foregroundStyle(SilliesTheme.secondary)
        }
      }
      ScrollViewReader { proxy in
        ScrollView {
          if model.transcript.isEmpty {
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
          } else {
            Text(model.transcript).font(.system(size: 14)).lineSpacing(6).textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          Color.clear.frame(height: 1).id(Self.endAnchor)
        }
        .onChange(of: model.transcript) { _, _ in
          if model.followsLiveTranscript { proxy.scrollTo(Self.endAnchor, anchor: .bottom) }
        }
        .onChange(of: model.followsLiveTranscript) { _, enabled in
          if enabled { proxy.scrollTo(Self.endAnchor, anchor: .bottom) }
        }
      }
      .frame(minHeight: Self.minimumTranscriptHeight, maxHeight: .infinity)
    }
    .padding(16).background(SilliesTheme.card, in: RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(SilliesTheme.border, lineWidth: 1))
  }
}
