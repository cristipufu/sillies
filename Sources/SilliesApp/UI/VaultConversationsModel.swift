import Foundation
import Observation
import SilliesCore

@MainActor struct VaultConversationPresentation {
  let repository: any ConversationRepository
  let open: (ConversationOwner, UUID?) async -> SessionFailure?
}

@MainActor @Observable final class VaultConversationsModel {
  private static let searchDebounce: Duration = .milliseconds(250)
  private let presentation: VaultConversationPresentation
  var query = ""
  private(set) var headers: [ConversationHeader] = []
  private var matches: [ConversationSearchMatch] = []
  private var appliedQuery: String?
  var results: [ConversationSearchMatch] { appliedQuery == query ? matches : [] }
  private(set) var loadFailure: String?
  private(set) var openFailure: SessionFailure?
  private(set) var isLoading = false
  private(set) var isOpening = false
  private var generation = UUID()
  @ObservationIgnored private var openTask: Task<Void, Never>?

  init(presentation: VaultConversationPresentation) { self.presentation = presentation }

  func load() async {
    let token = UUID()
    generation = token
    let requestedQuery = query
    isLoading = true
    defer { if token == generation { isLoading = false } }
    do {
      if requestedQuery.isEmpty {
        let loaded = try await presentation.repository.conversations()
        guard token == generation, query == requestedQuery, !Task.isCancelled else { return }
        headers = loaded
      } else {
        try await Task.sleep(for: Self.searchDebounce)
        let loaded = try await presentation.repository.search(.init(query: requestedQuery))
        guard token == generation, query == requestedQuery, !Task.isCancelled else { return }
        matches = loaded
        appliedQuery = requestedQuery
      }
      loadFailure = nil
    } catch {
      guard token == generation, !Task.isCancelled else { return }
      loadFailure = error.localizedDescription
      fputs("Conversation list failed: \(error)\n", stderr)
    }
  }

  func open(_ owner: ConversationOwner, messageID: UUID? = nil) {
    guard !isOpening else { return }
    isOpening = true
    openFailure = nil
    openTask = Task { [weak self, presentation] in
      guard !Task.isCancelled else { return }
      let failure = await presentation.open(owner, messageID)
      guard !Task.isCancelled else { return }
      self?.openFailure = failure
      self?.isOpening = false
      self?.openTask = nil
    }
  }

  func stop() {
    generation = UUID()
    isLoading = false
    isOpening = false
    openTask?.cancel()
    openTask = nil
  }
  isolated deinit { stop() }
}
