import SilliesCore
import SwiftUI

/// Shared by live capture and saved sessions so recovery always follows the typed failure.
struct SessionFailureNotice: View {
  let failure: SessionFailure
  var refreshScreenRecordingPermission: (() -> Void)? = nil

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
      VStack(alignment: .leading, spacing: 8) {
        Text(failure.message).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        if let recovery = failure.recovery {
          Button(settingsTitle(recovery)) { SessionRecovery.open(recovery) }
            .buttonStyle(.link)
          if recovery == .openScreenRecordingSettings, let refreshScreenRecordingPermission {
            Button("Refresh screen recording permission", action: refreshScreenRecordingPermission)
              .buttonStyle(.link)
              .help(
                "Resets stale permission from older local builds and opens screen recording settings."
              )
          }
        }
      }
      Spacer(minLength: 0)
    }.font(.callout).padding(12)
      .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
  }

  private func settingsTitle(_ action: SessionFailure.RecoveryAction) -> String {
    switch action {
    case .openMicrophoneSettings: "Open microphone settings"
    case .openScreenRecordingSettings: "Open screen recording settings"
    }
  }
}
