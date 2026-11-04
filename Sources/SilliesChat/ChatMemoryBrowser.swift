import Foundation
import Observation
import SilliesCore

/// One page of user-visible facts. Late reads cannot replace a refreshed or closed conversation.
@MainActor @Observable
package final class ChatMemoryBrowser {
  package private(set) var page = CompanionMemoryPage(facts: [], next: nil)
  package private(set) var isLoading = false
  package private(set) var failure: String?
  package private(set) var pageRevision = UUID()
  @ObservationIgnored private let repository: (any CompanionMemoryRepository)?
  @ObservationIgnored private var handle: ConversationHandle?
  @ObservationIgnored private var generation = UUID()

  package init(repository: (any CompanionMemoryRepository)?) { self.repository = repository }

  package func refresh(_ handle: ConversationHandle) async throws {
    if self.handle != handle { page = .init(facts: [], next: nil) }
    self.handle = handle
    try await load(.latest)
  }

  package func show(_ position: CompanionMemoryPageRequest.Position) async {
    do { try await load(position) } catch is CancellationError {
    } catch {
      fputs("Memory page read failed: \(error)\n", stderr)
    }
  }

  package func received(_ receipt: MemoryReceipt) {
    guard receipt.handle == handle else { return }
    invalidate()
    var facts = page.facts.filter { $0.id != receipt.saved.id }
    if page.previous == nil {
      facts.insert(receipt.saved, at: 0)
    }
    let hasMore = page.next != nil || facts.count > CompanionMemoryPageRequest.pageSize
    facts = Array(facts.prefix(CompanionMemoryPageRequest.pageSize))
    page = .init(
      facts: facts, next: hasMore ? facts.last.map(CompanionMemoryCursor.init) : nil,
      previous: page.previous)
  }

  package func invalidate() {
    generation = UUID()
    isLoading = false
  }

  private func load(_ position: CompanionMemoryPageRequest.Position) async throws {
    guard let repository, let handle else { return }
    let token = UUID()
    generation = token
    isLoading = true
    defer { if generation == token { isLoading = false } }
    do {
      var result = try await repository.memoryPage(.init(handle: handle, position: position))
      if result.facts.isEmpty, position != .latest, generation == token {
        try Task.checkCancellation()
        result = try await repository.memoryPage(.init(handle: handle))
      }
      try Task.checkCancellation()
      guard generation == token, self.handle == handle else { return }
      page = result
      pageRevision = UUID()
      failure = nil
    } catch {
      guard generation == token, self.handle == handle else { return }
      if !(error is CancellationError) { failure = error.localizedDescription }
      throw error
    }
  }
}
