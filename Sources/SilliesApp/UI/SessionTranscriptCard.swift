import SwiftUI

/// Recording and dictation share the same stable, selectable transcript viewport and follow controls.
struct SessionTranscriptCard<EmptyContent: View>: View {
  private static var minimumHeight: CGFloat { 160 }
  let text: String
  let isFinished: Bool
  @Binding var followsLive: Bool
  @ViewBuilder let emptyContent: () -> EmptyContent

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(isFinished ? "Transcript" : "Live transcript").font(.headline)
        Spacer()
        if !isFinished, !text.isEmpty {
          Toggle("Follow live", isOn: $followsLive).toggleStyle(.checkbox)
            .font(.caption).foregroundStyle(SilliesTheme.secondary)
        }
        if !followsLive, !text.isEmpty {
          Button("Jump to latest", systemImage: "arrow.down") { followsLive = true }
            .buttonStyle(.borderedProminent).controlSize(.small)
            .help("Show the newest speech and resume following the transcript")
        }
      }
      Group {
        if text.isEmpty {
          emptyContent()
        } else {
          LiveTranscriptTextView(text: text, followsLive: $followsLive)
        }
      }.frame(minHeight: Self.minimumHeight, maxHeight: .infinity)
    }
    .padding(16).background(SilliesTheme.card, in: RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(SilliesTheme.border, lineWidth: 1))
  }
}
