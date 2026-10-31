import Foundation

/// A deadline releases the caller even when model cancellation is slow. One model task may remain.
package actor BoundedTextCleanup {
  package init() {}
  package typealias Transform = @Sendable (String) async throws -> String
  package enum Outcome: Sendable {
    case completed(String)
    case failed(String)
    case timedOut, canceled, busy
    package var text: String? { if case .completed(let value) = self { value } else { nil } }
  }
  private var active: UUID?
  private var work: Task<Void, Never>?
  private var timeout: Task<Void, Never>?
  private var waiter: CheckedContinuation<Outcome, Never>?

  package func process(_ text: String, deadline: Duration, transform: @escaping Transform) async
    -> String?
  {
    await perform(text, deadline: deadline, transform: transform).text
  }
  package func perform(_ text: String, deadline: Duration, transform: @escaping Transform) async
    -> Outcome
  {
    guard !Task.isCancelled else { return .canceled }
    guard active == nil else { return .busy }
    let id = UUID()
    active = id
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        waiter = continuation
        work = Task {
          let result: Outcome
          do { result = .completed(try await transform(text)) } catch {
            result = .failed(error.localizedDescription)
          }
          complete(result, id: id)
        }
        timeout = Task {
          do { try await Task.sleep(for: deadline) } catch { return }
          expire(id, reason: .timedOut)
        }
      }
    } onCancel: {
      Task { await self.expire(id, reason: .canceled) }
    }
  }

  private func expire(_ id: UUID, reason: Outcome) {
    guard active == id else { return }
    waiter?.resume(returning: reason)
    waiter = nil
    work?.cancel()
  }
  private func complete(_ result: Outcome, id: UUID) {
    guard active == id else { return }
    timeout?.cancel()
    timeout = nil
    waiter?.resume(returning: result)
    waiter = nil
    work = nil
    active = nil
  }
}
