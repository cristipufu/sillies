import Foundation
import SilliesCore
import SilliesVault

/// Serial field edits. Worker reads return through modal-safe delivery before a synchronous mutation.
@MainActor final class VaultRecordEditor {
  struct Context {
    let revision: (UUID) -> Int
    let pending: (UUID) -> SessionRecord?
    let isRemoved: (UUID) -> Bool
    let save: (SessionRecord) -> Void
  }
  typealias Completion = @MainActor (Result<Bool, Error>) -> Void
  private struct Request {
    let id: UUID
    let edit: VaultRecordEdit
    let completion: Completion
  }
  private let load: @Sendable (UUID) async throws -> SessionRecord?
  private let context: Context
  private var requests: [Request] = []
  private var active: Request?
  private var waiters: [@MainActor () -> Void] = []
  init(load: @escaping @Sendable (UUID) async throws -> SessionRecord?, context: Context) {
    self.load = load
    self.context = context
  }
  func submit(id: UUID, edit: VaultRecordEdit, completion: @escaping Completion) {
    requests.append(.init(id: id, edit: edit, completion: completion))
    pump()
  }
  func flush(_ completion: @escaping @MainActor () -> Void) {
    if active == nil, requests.isEmpty { completion() } else { waiters.append(completion) }
  }
  private func pump() {
    guard active == nil else { return }
    guard !requests.isEmpty else {
      let completions = waiters
      waiters.removeAll()
      for complete in completions { complete() }
      return
    }
    active = requests.removeFirst()
    readCurrent()
  }
  private func readCurrent() {
    guard let request = active else { return }
    if context.isRemoved(request.id) {
      finish(.success(false))
      return
    }
    if let record = context.pending(request.id) {
      apply(request, to: record)
      return
    }
    let revision = context.revision(request.id)
    let id = request.id
    Task.detached { [weak self, load] in
      let result: Result<SessionRecord?, Error>
      do { result = .success(try await load(id)) } catch { result = .failure(error) }
      MainRunLoopDelivery.perform { self?.receive(result, revision: revision) }
    }
  }
  private func receive(_ result: Result<SessionRecord?, Error>, revision: Int) {
    guard let request = active else { return }
    guard context.revision(request.id) == revision else {
      readCurrent()
      return
    }
    do {
      guard !context.isRemoved(request.id),
        let record = try (context.pending(request.id) ?? result.get())
      else {
        finish(.success(false))
        return
      }
      apply(request, to: record)
    } catch { finish(.failure(error)) }
  }
  private func apply(_ request: Request, to record: SessionRecord) {
    var edited = record
    let accepted = request.edit.apply(to: &edited)
    if accepted { context.save(edited) }
    finish(.success(accepted))
  }
  private func finish(_ result: Result<Bool, Error>) {
    let request = active
    active = nil
    request?.completion(result)
    MainRunLoopDelivery.perform { [weak self] in self?.pump() }
  }
}
