import SilliesCore
import SwiftUI

struct AudioSessionView: View {
  @Environment(\.silliesTheme) private var theme
  private static let contentSpacing: CGFloat = 12
  private static let contentPadding: CGFloat = 20
  let model: AudioSessionPresentation

  var body: some View {
    content
      .frame(
        minWidth: SessionWindowLayout.minimumSize.width,
        minHeight: SessionWindowLayout.minimumSize.height
      )
      .background(theme.paper).foregroundStyle(theme.ink)
      .tint(theme.accent)
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: Self.contentSpacing) {
      AudioSessionHeader(model: model)
        .fixedSize(horizontal: false, vertical: true)
      AudioLanguagePicker(model: model)
        .fixedSize(horizontal: false, vertical: true)
      AudioSessionNotices(model: model)
        .fixedSize(horizontal: false, vertical: true)
      if model.kind == .participate {
        AudioMeetingPanes(model: model)
      } else {
        AudioTranscriptView(model: model)
      }
      footer
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(Self.contentPadding)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var footer: some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: "lock.shield").foregroundStyle(theme.accent)
      Text(footerMessage)
        .fixedSize(horizontal: false, vertical: true)
    }
    .font(.caption).foregroundStyle(theme.secondary)
  }

  private var footerMessage: String {
    switch model.phase {
    case .finished:
      String(localized: "Saved on this Mac. Open the Vault for your transcript and notes.")
    case .paused:
      String(localized: "Paused audio isn’t saved or transcribed. Resume whenever you’re ready.")
    case .failed:
      String(localized: "Choose Finish & Save to keep the available transcript and recording.")
    default:
      String(
        localized:
          "Processed on this Mac. Closing this window keeps the session running; Finish & Save stops it."
      )
    }
  }
}
