import SilliesCore
import SwiftUI

/// Shared by live capture and saved sessions so recovery always follows the typed failure.
struct SessionFailureNotice: View {
  let failure: SessionFailure
  var refreshScreenRecordingPermission: (() -> Void)? = nil

  var body: some View {
    SessionWarningNotice(message: failure.message) {
      if let recovery = failure.recovery {
        Button(settingsTitle(recovery)) { SessionRecovery.open(recovery) }
          .buttonStyle(SoftButtonStyle())
        if recovery == .openScreenRecordingSettings, let refreshScreenRecordingPermission {
          Button("Refresh screen recording permission", action: refreshScreenRecordingPermission)
            .buttonStyle(.link)
            .help(
              "Resets stale permission from older local builds and opens screen recording settings."
            )
        }
      }
    }
  }

  private func settingsTitle(_ action: SessionFailure.RecoveryAction) -> String {
    switch action {
    case .openMicrophoneSettings: "Open microphone settings"
    case .openScreenRecordingSettings: "Open screen recording settings"
    case .openAccessibilitySettings: "Enable text insertion…"
    }
  }
}
