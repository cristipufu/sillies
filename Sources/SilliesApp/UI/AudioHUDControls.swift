import SwiftUI

struct AudioHUDControls: View {
  let session: AudioSessionPresentation
  let open: () -> Void

  var body: some View {
    HStack(spacing: 6) {
      Button(action: open) {
        Image(systemName: session.hasUnreadSuggestion ? "pawprint.fill" : "text.bubble")
          .foregroundStyle(session.hasUnreadSuggestion ? Color.orange : SilliesTheme.accent)
          .frame(width: 24, height: 24)
      }.help(
        session.hasUnreadSuggestion
          ? "A meeting suggestion is ready" : "Open session and transcript"
      )
      .accessibilityLabel(session.hasUnreadSuggestion ? "Read meeting suggestion" : "Open session")
      Button {
        if session.isPaused { session.onResume?() } else { session.onPause?() }
      } label: {
        Image(systemName: session.isPaused ? "play.fill" : "pause.fill").frame(
          width: 24, height: 24)
      }.disabled(!session.canPause).help(session.isPaused ? "Resume" : "Pause")
    }.buttonStyle(.plain)
  }
}
