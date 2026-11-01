import Foundation

/// One bounded reply, one reader. Text can finish generating while a large voice waits for memory.
package actor SpeechTextStream {
  private static let maximumQueuedCharacters = 4_000
  private static let maximumQueuedBytes = 16_000
  private var phrases: [String] = []
  private var totalCharacters = 0
  private var totalBytes = 0
  private var ended = false
  private var failure: (any Error)?
  private var waiter: CheckedContinuation<String?, Error>?
  private var started = false
  private var startWaiter: CheckedContinuation<Bool, Error>?
  package init() {}

  package func textStarted() {
    guard failure == nil, !ended else { return }
    started = true
    startWaiter?.resume(returning: true)
    startWaiter = nil
  }

  package func waitForTextStart() async throws -> Bool {
    try await withTaskCancellationHandler {
      try Task.checkCancellation()
      if let failure { throw failure }
      if started { return true }
      if ended { return false }
      guard startWaiter == nil else { throw TTSError.busy }
      return try await withCheckedThrowingContinuation { startWaiter = $0 }
    } onCancel: {
      Task { await self.cancel() }
    }
  }
  package func append(_ text: String) throws {
    if let failure { throw failure }
    guard !ended, !text.isEmpty, text.count <= SpeechSynthesisRequest.maximumTextCharacters,
      text.count <= Self.maximumQueuedCharacters - totalCharacters,
      text.utf8.count <= Self.maximumQueuedBytes - totalBytes
    else { throw TTSError.invalidRequest }
    textStarted()
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
      if let failure { throw failure }
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
    startWaiter?.resume(returning: started)
    startWaiter = nil
    waiter?.resume(returning: nil)
    waiter = nil
  }
  package func cancel() {
    fail(CancellationError())
  }
  package func fail(_ error: any Error) {
    guard failure == nil else { return }
    failure = error
    phrases.removeAll()
    waiter?.resume(throwing: error)
    waiter = nil
    startWaiter?.resume(throwing: error)
    startWaiter = nil
  }
}
