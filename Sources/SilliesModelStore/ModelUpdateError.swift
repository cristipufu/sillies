import Foundation

package enum ModelUpdateError: LocalizedError {
  case metadataUnavailable, metadataTooLarge, layoutChanged, incompatibleRuntime
  package var errorDescription: String? {
    switch self {
    case .metadataUnavailable:
      String(localized: "Couldn’t check the model publisher. Your installed model still works.")
    case .metadataTooLarge:
      String(localized: "The publisher’s model metadata exceeded the supported size.")
    case .layoutChanged:
      String(
        localized: "The publisher changed the model format. This revision needs an app update.")
    case .incompatibleRuntime:
      String(
        localized:
          "This revision is incompatible with the installed speech runtime. Your previous model is still selected."
      )
    }
  }
}
