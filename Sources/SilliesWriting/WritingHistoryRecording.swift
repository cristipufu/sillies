import SilliesCore

@MainActor package protocol WritingHistoryRecording: AnyObject {
  var persistence: WritingHistoryPersistence { get }
  func save(_ result: WritingResult)
  func retry()
  /// Implementations must deliver completion during native modal termination, too.
  func flush(
    completion: @escaping @MainActor @Sendable (Result<Void, WritingHistoryFailure>) -> Void)
}
