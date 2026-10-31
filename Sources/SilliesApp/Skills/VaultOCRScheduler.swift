import Foundation

/// One OCR job at a time, with no decoded images queued. Cancellation retains pending metadata.
@MainActor final class VaultOCRScheduler {
  struct Request {
    let id: UUID
    let url: URL
  }
  typealias Recognize = @Sendable (URL) async throws -> String
  var next: () -> Request? = { nil }
  var complete: (UUID, Result<String, Error>) -> Void = { _, _ in }
  private let recognize: Recognize
  private var enabled = true
  private var work: Task<Void, Never>?
  init(recognize: @escaping Recognize = { try await WindowTextRecognition.recognize($0) }) {
    self.recognize = recognize
  }
  func resume() {
    enabled = true
    pump()
  }
  func stop() {
    enabled = false
    work?.cancel()
  }
  func pump() {
    guard enabled, work == nil, let request = next() else { return }
    work = Task { [weak self, recognize] in
      let result: Result<String, Error>
      do { result = .success(try await recognize(request.url)) } catch { result = .failure(error) }
      guard let self else { return }
      if !Task.isCancelled, self.enabled { self.complete(request.id, result) }
      self.work = nil
      self.pump()
    }
  }
}
