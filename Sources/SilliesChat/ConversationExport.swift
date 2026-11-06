import Foundation
import Observation
import SilliesCore

/// Owns export preparation and a cancellable writer; final delivery also drains during termination.
@MainActor @Observable
package final class ConversationExport {
  package typealias Delivery = @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void
  package private(set) var isExporting = false
  package private(set) var exportedMessages = 0
  package private(set) var notice: String?
  package var isAvailable: Bool {
    history.configuration.conversations is any ConversationExporting && history.isLoaded
  }
  private let history: ChatHistory
  private let companionName: String
  private let deliver: Delivery
  @ObservationIgnored private var preparation: Task<Void, Never>?
  @ObservationIgnored private var writer: Task<Void, Never>?
  @ObservationIgnored private var generation = UUID()
  @ObservationIgnored private var finishWaiters: [@MainActor () -> Void] = []

  private enum Outcome: Sendable {
    case exported(Int)
    case cancelled, failed
  }

  package init(history: ChatHistory, companionName: String, deliver: @escaping Delivery) {
    self.history = history
    self.companionName = companionName
    self.deliver = deliver
  }

  package func start(to destination: URL) {
    guard !isExporting, let handle = history.handle,
      let exporter = history.configuration.conversations as? any ConversationExporting
    else { return }
    let token = UUID()
    generation = token
    exportedMessages = 0
    notice = nil
    isExporting = true
    preparation = Task { [weak self, history] in
      do {
        try await history.flush()
        try Task.checkCancellation()
        guard let self, self.generation == token else { return }
        guard self.history.handle == handle else {
          self.complete(.failed, generation: token)
          return
        }
        self.preparation = nil
        self.beginWriting(exporter, handle: handle, to: destination, generation: token)
      } catch is CancellationError {
        self?.complete(.cancelled, generation: token)
      } catch {
        fputs("Conversation export preparation failed: \(error)\n", stderr)
        self?.complete(.failed, generation: token)
      }
    }
  }

  private func beginWriting(
    _ exporter: any ConversationExporting, handle: ConversationHandle, to destination: URL,
    generation token: UUID
  ) {
    let request = ConversationExportRequest(handle: handle, companionName: companionName)
    writer = Task.detached(priority: .utility) { [self, deliver] in
      let outcome: Outcome
      do {
        let count = try await exporter.exportConversation(request, to: destination) { count in
          // At most one progress delivery is outstanding, including in the modal termination loop.
          await withCheckedContinuation { continuation in
            deliver {
              if self.generation == token, self.isExporting { self.exportedMessages = count }
              continuation.resume()
            }
          }
        }
        outcome = .exported(count)
      } catch is CancellationError {
        outcome = .cancelled
      } catch {
        fputs("Conversation export failed: \(error)\n", stderr)
        outcome = .failed
      }
      deliver { self.complete(outcome, generation: token) }
    }
  }

  package func cancel() {
    preparation?.cancel()
    preparation = nil
    if let writer {
      writer.cancel()
    } else if isExporting {
      complete(.cancelled, generation: generation)
    }
  }

  package func finish(completion: @escaping @MainActor () -> Void) {
    guard isExporting else {
      completion()
      return
    }
    finishWaiters.append(completion)
    cancel()
  }

  private func complete(_ outcome: Outcome, generation token: UUID) {
    guard generation == token else { return }
    generation = UUID()
    isExporting = false
    preparation = nil
    writer = nil
    switch outcome {
    case .exported(let count):
      exportedMessages = count
      notice = String(localized: "Conversation exported.")
    case .cancelled: notice = String(localized: "Export cancelled.")
    case .failed:
      notice = String(
        localized:
          "Couldn’t export the conversation. Your messages are safe; choose a writable folder and try again."
      )
    }
    let waiters = finishWaiters
    finishWaiters.removeAll()
    for completion in waiters { completion() }
  }

  package func dismissNotice() { notice = nil }
}
