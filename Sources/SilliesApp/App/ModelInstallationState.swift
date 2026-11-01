import Foundation

enum ModelInstallationState: Equatable {
  case absent, downloaded, ready, paused, preparing, validating, cancelling
  case verifying(Double)
  case downloading(Double)
  case failed(String)
  case preparationFailed(String)
  var label: String {
    switch self {
    case .absent: String(localized: "Not downloaded")
    case .downloaded: String(localized: "Downloaded")
    case .ready: String(localized: "Ready on this Mac")
    case .paused: String(localized: "Download paused")
    case .verifying(let fraction):
      String(localized: "Checking downloaded file · \(Int(fraction * 100))% downloaded")
    case .preparing: String(localized: "Preparing for this Mac…")
    case .validating: String(localized: "Checking compatibility on this Mac…")
    case .cancelling: String(localized: "Cancelling…")
    case .downloading(let fraction): String(localized: "Downloading · \(Int(fraction * 100))%")
    case .failed(let message), .preparationFailed(let message): message
    }
  }
  var downloadFraction: Double? {
    switch self {
    case .downloading(let fraction), .verifying(let fraction): fraction
    default: nil
    }
  }
  var isProcessing: Bool {
    switch self {
    case .verifying, .preparing, .validating: true
    default: false
    }
  }
}
