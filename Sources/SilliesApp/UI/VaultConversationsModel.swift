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
  let reader: VaultConversationReaderModel
  var query = ""
  var companionID: String?
  struct SearchIdentity: Hashable {
    let query: String
    let companionID: String?
  }
  var searchIdentity: SearchIdentity { .init(query: query, companionID: companionID) }
  private(set) var headers: [ConversationHeader] = []
  private var matches: [ConversationSearchMatch] = []
  private var appliedQuery: SearchIdentity?
  var results: [ConversationSearchMatch] { appliedQuery == searchIdentity ? matches : [] }
  private(set) var loadFailure: String?
  private(set) var openFailure: SessionFailure?
  private(set) var isLoading = false
  private(set) var isOpening = false
  private var generation = UUID()
  @ObservationIgnored private var openTask: Task<Void, Never>?

  init(presentation: VaultConversationPresentation) {
    self.presentation = presentation
    reader = .init(repository: presentation.repository)
  }

  func load() async {
    reader.resume()
    let token = UUID()
    generation = token
    let request = searchIdentity
    isLoading = true
    defer { if token == generation { isLoading = false } }
    do {
      if request.query.isEmpty {
        let loaded = try await presentation.repository.conversations()
        guard token == generation, searchIdentity == request, !Task.isCancelled else { return }
        headers = loaded.filter { request.companionID == nil || $0.owner.id == request.companionID }
      } else {
        try await Task.sleep(for: Self.searchDebounce)
        let loaded = try await presentation.repository.search(
          .init(companionID: request.companionID, query: request.query))
        guard token == generation, searchIdentity == request, !Task.isCancelled else { return }
        matches = loaded
        appliedQuery = request
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

  func companionChoices(matching text: String) async throws -> [VaultSourceFacet] {
    try await presentation.repository.conversations()
      .filter { text.isEmpty || $0.owner.name.localizedStandardContains(text) }
      .prefix(VaultSourceFacet.maximumChoices)
      .map { .init(id: $0.owner.id, title: $0.owner.name) }
  }

  func stop() {
    reader.stop()
    generation = UUID()
    isLoading = false
    isOpening = false
    openTask?.cancel()
    openTask = nil
  }
  isolated deinit { stop() }
}
