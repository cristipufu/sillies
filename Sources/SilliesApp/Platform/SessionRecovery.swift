import AppKit
import SilliesCore

enum SessionRecovery {
  static func settingsURL(for action: SessionFailure.RecoveryAction) -> URL? {
    let pane: String
    switch action {
    case .openMicrophoneSettings: pane = "Privacy_Microphone"
    case .openScreenRecordingSettings: pane = "Privacy_ScreenCapture"
    }
    return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")
  }

  @MainActor static func open(_ action: SessionFailure.RecoveryAction) {
    guard let url = settingsURL(for: action) else { return }
    NSWorkspace.shared.open(url)
  }
}
