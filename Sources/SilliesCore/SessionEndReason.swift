import Foundation

public enum SessionEndReason: Sendable {
  case userFinished
  case sourceClosed
}

extension SessionFailure {
  /// A verified source closure explains capture shutdown, never a permission or data-save failure.
  public func requiresAttention(ending reason: SessionEndReason) -> Bool {
    switch (reason, category) {
    case (.sourceClosed, .captureInterrupted): false
    default: true
    }
  }
}
