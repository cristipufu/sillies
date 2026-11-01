import SwiftUI

struct AudioHUDControls: View {
  @Environment(\.silliesTheme) private var theme
  let session: AudioSessionPresentation
  let open: () -> Void

  var body: some View {
    HStack(spacing: 6) {
      Button(action: open) {
        Image(systemName: session.hasUnreadSuggestion ? "pawprint.fill" : "text.bubble")
          .foregroundStyle(session.hasUnreadSuggestion ? theme.warning : theme.accent)
          .frame(width: 24, height: 24)
      }.help(
        session.hasUnreadSuggestion
          ? String(localized: "A meeting suggestion is ready")
          : String(localized: "Open session and transcript")
      )
      .accessibilityLabel(
        session.hasUnreadSuggestion
          ? String(localized: "Read meeting suggestion") : String(localized: "Open session"))
      Button {
        if session.isPaused { session.onResume?() } else { session.onPause?() }
      } label: {
        Image(systemName: session.isPaused ? "play.fill" : "pause.fill").frame(
          width: 24, height: 24)
      }.disabled(!session.canPause).help(
        session.isPaused ? String(localized: "Resume") : String(localized: "Pause"))
    }.buttonStyle(.plain)
  }
}
