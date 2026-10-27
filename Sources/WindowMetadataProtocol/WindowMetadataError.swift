import Foundation

public enum WindowMetadataError: Error, LocalizedError {
  case responseTooLarge
  case invalidResponse
  case responseTimedOut
  case connectionClosed
  case snapshotUnavailable

  public var errorDescription: String? {
    switch self {
    case .responseTooLarge: "Window metadata exceeded the response size limit."
    case .invalidResponse: "The window metadata helper returned an invalid response."
    case .responseTimedOut: "The window metadata helper did not respond before its deadline."
    case .connectionClosed: "The window metadata helper closed its connection."
    case .snapshotUnavailable: "WindowServer could not provide a window metadata snapshot."
    }
  }
}
