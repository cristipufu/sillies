import Foundation
import Observation
import SilliesCore

@MainActor @Observable final class VaultConversationReaderModel {
  private let repository: any ConversationRepository
  private(set) var owner: ConversationOwner?
  private(set) var page: ConversationPage?
  private(set) var isLoading = false
  private(set) var error: String?
  private var handle: ConversationHandle?
  private var requestedMessageID: UUID?
  private var failedPosition: ConversationPageRequest.Position?
  private var generation = UUID()
  @ObservationIgnored private var task: Task<Void, Never>?

  init(repository: any ConversationRepository) { self.repository = repository }

  func select(_ owner: ConversationOwner, messageID: UUID? = nil) {
    clear()
    self.owner = owner
    requestedMessageID = messageID
    let token = generation
    isLoading = true
    task = Task { [weak self, repository] in
      do {
        let snapshot = try await repository.open(owner)
        let page: ConversationPage
        if let messageID {
          page = try await repository.page(
            .init(handle: snapshot.handle, position: .around(messageID)))
        } else {
          page = snapshot.page
        }
        guard let self, generation == token, !Task.isCancelled else { return }
        handle = snapshot.handle
        self.page = page
        error = nil
        isLoading = false
      } catch is CancellationError {
        guard let self, generation == token else { return }
        isLoading = false
      } catch {
        guard let self, generation == token, !Task.isCancelled else { return }
        self.error = error.localizedDescription
        isLoading = false
      }
    }
  }

  func resume() {
    guard let owner, page == nil, error == nil, !isLoading else { return }
    select(owner, messageID: requestedMessageID)
  }

  func retry() async {
    guard let owner, !isLoading else { return }
    if let failedPosition {
      await move(failedPosition)
    } else {
      select(owner, messageID: requestedMessageID)
    }
  }

  func move(_ position: ConversationPageRequest.Position) async {
    guard let handle, !isLoading else { return }
    let token = generation
    isLoading = true
    defer { if generation == token { isLoading = false } }
    do {
      let page = try await repository.page(.init(handle: handle, position: position))
      guard generation == token, !Task.isCancelled else { return }
      self.page = page
      error = nil
      failedPosition = nil
    } catch is CancellationError { return } catch {
      if generation == token, !Task.isCancelled {
        self.error = error.localizedDescription
        failedPosition = position
      }
    }
  }

  func stop() {
    generation = UUID()
    task?.cancel()
    task = nil
    isLoading = false
  }
  func clear() {
    stop()
    owner = nil
    page = nil
    handle = nil
    requestedMessageID = nil
    failedPosition = nil
    error = nil
  }
  isolated deinit { task?.cancel() }
}
