import SilliesCore
import SwiftUI

/// Recording actions share Talk's compact controls and native speech-bubble surface.
struct RecordingHUDView: View {
  private static let contentWidth: CGFloat = 320
  @Environment(\.silliesTheme) private var theme
  let model: CompanionHUDModel
  let state: CompanionBindingState

  var body: some View {
    if case .active(_, let skill, _, let status, let level) = state {
      HStack(spacing: SessionHUDMetrics.spacing) {
        SessionAudioIndicator(level: level, isCapturing: model.audioSession?.phase == .capturing)
        SessionHUDLabel(
          title: "\(skill.title) · \(model.sourceName(for: state))",
          status: status, layout: .flexible)
        if let session = model.audioSession {
          AudioHUDControls(session: session, open: { model.onOpenSession?() })
        }
        if let title = skill.stopActionTitle {
          SessionHUDAction(title: title) { model.onStopSkill?() }
        }
        SessionHUDDismiss(title: String(localized: "Cancel skill")) { model.onUnbind?() }
      }
      .foregroundStyle(theme.ink).tint(theme.accent)
      .frame(width: Self.contentWidth)
      .padding(SessionHUDMetrics.contentInset)
    }
  }
}
