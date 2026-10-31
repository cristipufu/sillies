import Foundation

/// One OCR job at a time, with no decoded images queued. Cancellation retains pending metadata.
@MainActor final class VaultOCRScheduler {
  struct Request {
    let id: UUID
    let url: URL
    let revision: UUID
  }
  typealias Recognize = @Sendable (URL) async throws -> String
  var next: () async throws -> Request? = { nil }
  var complete: (Request, Result<String, Error>) async -> Void = { _, _ in }
  private let recognize: Recognize
  private var enabled = true
  private var requested = false
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
    guard enabled else { return }
    requested = true
    startNext()
  }
  private func startNext() {
    guard enabled, requested, work == nil else { return }
    requested = false
    work = Task { [weak self, recognize] in
      guard let self else { return }
      do {
        if let request = try await self.next(), !Task.isCancelled {
          let result: Result<String, Error>
          do { result = .success(try await recognize(request.url)) } catch {
            result = .failure(error)
          }
          if !Task.isCancelled, self.enabled { await self.complete(request, result) }
          self.requested = true
        }
      } catch {
        fputs("Could not load pending screenshot text: \(error)\n", stderr)
      }
      self.work = nil
      self.startNext()
    }
  }
}
