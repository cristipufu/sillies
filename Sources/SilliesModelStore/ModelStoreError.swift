import Foundation

package enum ModelStoreError: LocalizedError {
  case invalidManifest, unknownModel, notInstalled, inUse, busy
  case invalidArtifact(String)
  case insufficientSpace, unsafePath

  package var errorDescription: String? {
    switch self {
    case .invalidManifest: String(localized: "The transcription model catalog is invalid.")
    case .unknownModel:
      String(localized: "This transcription model is not available in this version of Sillies.")
    case .notInstalled:
      String(localized: "Download this model in Settings before starting a session.")
    case .inUse:
      String(
        localized:
          "This model is in use. Finish the audio session before changing its installed version.")
    case .busy: String(localized: "A model operation is already in progress.")
    case .invalidArtifact(let name):
      String(localized: "The downloaded file \(name) could not be verified. Retry the download.")
    case .insufficientSpace:
      String(localized: "There is not enough free space to install this model.")
    case .unsafePath: String(localized: "The model folder contains an unexpected file or link.")
    }
  }
}
