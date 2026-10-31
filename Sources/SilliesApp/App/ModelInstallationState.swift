import Foundation

enum ModelInstallationState: Equatable {
  case absent, downloaded, ready, paused, preparing, validating, cancelling
  case verifying(Double)
  case downloading(Double)
  case failed(String)
  case preparationFailed(String)
  var label: String {
    switch self {
    case .absent: "Not downloaded"
    case .downloaded: "Downloaded"
    case .ready: "Ready on this Mac"
    case .paused: "Download paused"
    case .verifying(let fraction): "Checking downloaded file · \(Int(fraction * 100))% downloaded"
    case .preparing: "Preparing for this Mac…"
    case .validating: "Checking compatibility on this Mac…"
    case .cancelling: "Cancelling…"
    case .downloading(let fraction): "Downloading · \(Int(fraction * 100))%"
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
