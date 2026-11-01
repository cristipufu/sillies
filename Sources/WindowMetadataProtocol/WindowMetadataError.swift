import Foundation

public enum WindowMetadataError: Error, LocalizedError {
  case responseTooLarge
  case invalidResponse
  case responseTimedOut
  case connectionClosed
  case snapshotUnavailable

  public var errorDescription: String? {
    switch self {
    case .responseTooLarge: String(localized: "Window metadata exceeded the response size limit.")
    case .invalidResponse:
      String(localized: "The window metadata helper returned an invalid response.")
    case .responseTimedOut:
      String(localized: "The window metadata helper did not respond before its deadline.")
    case .connectionClosed: String(localized: "The window metadata helper closed its connection.")
    case .snapshotUnavailable:
      String(localized: "WindowServer could not provide a window metadata snapshot.")
    }
  }
}
