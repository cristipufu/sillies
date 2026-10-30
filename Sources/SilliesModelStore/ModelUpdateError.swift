import Foundation

package enum ModelUpdateError: LocalizedError {
  case metadataUnavailable, metadataTooLarge, layoutChanged, incompatibleRuntime
  package var errorDescription: String? {
    switch self {
    case .metadataUnavailable:
      "Couldn’t check the model publisher. Your installed model still works."
    case .metadataTooLarge: "The publisher’s model metadata exceeded the supported size."
    case .layoutChanged:
      "The publisher changed the model format. This revision needs an app update."
    case .incompatibleRuntime:
      "This revision is incompatible with the installed speech runtime. Your previous model is still selected."
    }
  }
}
