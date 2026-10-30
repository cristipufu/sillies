import Foundation

package enum ModelStoreError: LocalizedError {
  case invalidManifest, unknownModel, notInstalled, inUse, busy
  case invalidArtifact(String)
  case insufficientSpace, unsafePath

  package var errorDescription: String? {
    switch self {
    case .invalidManifest: "The transcription model catalog is invalid."
    case .unknownModel: "This transcription model is not available in this version of Sillies."
    case .notInstalled: "Download this model in Settings before starting a session."
    case .inUse:
      "This model is in use. Finish the audio session before changing its installed version."
    case .busy: "A model operation is already in progress."
    case .invalidArtifact(let name):
      "The downloaded file \(name) could not be verified. Retry the download."
    case .insufficientSpace: "There is not enough free space to install this model."
    case .unsafePath: "The model folder contains an unexpected file or link."
    }
  }
}
