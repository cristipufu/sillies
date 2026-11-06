import SwiftUI

struct AudioHUDControls: View {
  @Environment(\.silliesTheme) private var theme
  let session: AudioSessionPresentation
  let open: () -> Void

  var body: some View {
    HStack(spacing: SessionHUDMetrics.spacing) {
      Button(action: open) {
        Image(systemName: session.hasUnreadSuggestion ? "pawprint.fill" : "text.bubble")
          .foregroundStyle(session.hasUnreadSuggestion ? theme.warning : theme.accent)
          .frame(width: SessionHUDMetrics.controlSize, height: SessionHUDMetrics.controlSize)
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
          width: SessionHUDMetrics.controlSize, height: SessionHUDMetrics.controlSize)
      }.disabled(!session.canPause).help(
        session.isPaused ? String(localized: "Resume") : String(localized: "Pause"))
    }.buttonStyle(.plain)
  }
}
