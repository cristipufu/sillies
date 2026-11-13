import AVFoundation
import CoreGraphics
import SilliesCore

/// Permission prompts only run in response to a setup button; inspection never starts capture.
enum SetupPermissions {
  static func isGranted(_ permission: SessionFailure.RecoveryAction) async -> Bool {
    switch permission {
    case .openMicrophoneSettings: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    case .openScreenRecordingSettings:
      await Task.detached { CGPreflightScreenCaptureAccess() }.value
    case .openAccessibilitySettings, .openSystemAudioRecordingSettings: false
    }
  }

  @MainActor static func request(_ permission: SessionFailure.RecoveryAction) async {
    switch permission {
    case .openMicrophoneSettings:
      if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
        _ = await AVCaptureDevice.requestAccess(for: .audio)
      } else {
        SessionRecovery.open(permission)
      }
    case .openScreenRecordingSettings:
      let granted = await Task.detached { CGRequestScreenCaptureAccess() }.value
      if !granted { SessionRecovery.open(permission) }
    case .openAccessibilitySettings, .openSystemAudioRecordingSettings:
      SessionRecovery.open(permission)
    }
  }
}
