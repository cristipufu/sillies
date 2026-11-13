import CoreAudio
import Foundation
import SilliesCore

enum CoreAudioCaptureError: Error {
  enum Operation: Sendable {
    case properties, createTap, createDevice, createProcessor, observe, start
    case stop, removeObserver, destroyProcessor, destroyDevice, destroyTap, copyPacket
  }
  case unsupported
  case native(Operation, OSStatus)

  func failure(category: SessionFailure.Category) -> SessionFailure {
    switch self {
    case .unsupported:
      return .init(
        category: category,
        message: String(
          localized:
            "Application audio is unavailable. Finish and start a new session."))
    case .native(_, let status) where status == kAudioDevicePermissionsError:
      return .permissionDenied(.openSystemAudioRecordingSettings)
    case .native(_, let status):
      return .init(
        category: category,
        message: String(
          localized: "Application audio capture failed (Core Audio error \(Int(status)))."))
    }
  }
}
