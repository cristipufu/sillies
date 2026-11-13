import SilliesCore
import SwiftUI

struct ChatSourcePassageView: View {
  enum Presentation { case card, detail }
  @Environment(\.silliesTheme) private var theme
  let passage: VaultEvidencePassage
  let source: ChatSource
  let vault: ChatVaultPresentation
  let presentation: Presentation

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Button {
        vault.openPassage(passage, .read)
      } label: {
        HStack(spacing: 6) {
          Text(passage.reference.location.section.title)
          if let seconds = passage.startSeconds {
            Text(SessionRecord.formatDuration(seconds)).monospacedDigit()
          }
          if let speaker = passage.speaker { Text(speaker) }
          Image(systemName: "arrow.up.forward")
        }.font(.caption).foregroundStyle(theme.accent)
      }.buttonStyle(.plain).help("Open in Vault")
      Text(passage.text).font(.caption).foregroundStyle(theme.secondary).textSelection(.enabled)
        .lineLimit(presentation == .card ? 3 : nil)
      if source.hasRecording, passage.startSeconds != nil {
        Button("Play from here", systemImage: "play.circle") { vault.openPassage(passage, .play) }
          .buttonStyle(.plain).font(.caption).foregroundStyle(theme.accent)
      }
    }
  }
}
