import Foundation

/// One bounded reply, one reader. Text can finish generating while a large voice waits for memory.
package actor SpeechTextStream {
  private static let maximumQueuedCharacters = 4_000
  private static let maximumQueuedBytes = 16_000
  private var phrases: [String] = []
  private var totalCharacters = 0
  private var totalBytes = 0
  private var ended = false
  private var cancelled = false
  private var waiter: CheckedContinuation<String?, Error>?
  package init() {}
  package func append(_ text: String) throws {
    guard !cancelled else { throw CancellationError() }
    guard !ended, !text.isEmpty, text.count <= SpeechSynthesisRequest.maximumTextCharacters,
      text.count <= Self.maximumQueuedCharacters - totalCharacters,
      text.utf8.count <= Self.maximumQueuedBytes - totalBytes
    else { throw TTSError.invalidRequest }
    totalCharacters += text.count
    totalBytes += text.utf8.count
    if let waiter {
      self.waiter = nil
      waiter.resume(returning: text)
    } else {
      phrases.append(text)
    }
  }
  package func next() async throws -> String? {
    try await withTaskCancellationHandler {
      try Task.checkCancellation()
      guard !cancelled else { throw CancellationError() }
      if !phrases.isEmpty { return phrases.removeFirst() }
      if ended { return nil }
      guard waiter == nil else { throw TTSError.busy }
      return try await withCheckedThrowingContinuation { waiter = $0 }
    } onCancel: {
      Task { await self.cancel() }
    }
  }
  package func finish() {
    ended = true
    waiter?.resume(returning: nil)
    waiter = nil
  }
  package func cancel() {
    cancelled = true
    phrases.removeAll()
    waiter?.resume(throwing: CancellationError())
    waiter = nil
  }
}
