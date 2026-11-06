import SilliesCore
import SwiftUI

/// The full transcript replaces the detail pane; its native viewport is never nested in a scroll view.
struct VaultTranscriptReader: View {
  @Environment(\.silliesTheme) private var theme
  let record: SessionRecord
  let model: SessionVaultModel
  let isVisible: Bool

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        Button(action: model.closeTranscript) { Image(systemName: "chevron.left") }
          .buttonStyle(.plain).accessibilityLabel("Back").keyboardShortcut(.cancelAction)
        Text("Transcript").font(.headline)
        Spacer()
        Button("Copy Transcript", systemImage: "doc.on.doc") {
          model.copyText(record.transcript, feedback: String(localized: "Transcript copied"))
        }
        if model.canPopOutTranscript {
          Button("Open in new window", systemImage: "arrow.up.forward.square") {
            model.popOutTranscript(record)
          }
        }
      }.padding(18)
      Divider().overlay(theme.border)
      LiveTranscriptTextView(
        text: record.transcript, followsLive: .constant(false),
        presentation: isVisible ? .visible : .concealed
      )
      .padding(18)
    }.background(theme.paper)
  }
}
