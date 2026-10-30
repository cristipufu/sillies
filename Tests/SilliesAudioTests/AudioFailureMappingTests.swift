import Foundation
import ScreenCaptureKit
import SilliesCore
import Testing

@testable import SilliesAudio

@Test func applicationAudioPermissionRecoveryUsesNativeErrorIdentity() {
  let denied = NSError(
    domain: SCStreamErrorDomain, code: SCStreamError.Code.userDeclined.rawValue,
    userInfo: [NSLocalizedDescriptionKey: "Accès refusé."])
  let failure = ApplicationAudioSource.captureFailure(denied)
  #expect(failure.category == .permissionDenied)
  #expect(failure.recovery == .openScreenRecordingSettings)
  let unrelated = NSError(
    domain: "Fixture", code: denied.code,
    userInfo: [NSLocalizedDescriptionKey: "Screen recording permission and system settings"])
  #expect(ApplicationAudioSource.captureFailure(unrelated).recovery == nil)
}
