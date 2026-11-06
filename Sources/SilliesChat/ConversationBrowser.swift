import Foundation
import Observation
import SilliesCore

/// Browsing never replaces the recent messages supplied to inference.
@MainActor @Observable
package final class ConversationBrowser {
  package private(set) var page: ConversationPage?
  package private(set) var matches: [ConversationSearchMatch] = []
  package private(set) var isLoading = false
  package private(set) var isSearching = false
  package private(set) var searchedQuery = ""
  package private(set) var failure: String?
  package private(set) var focusedMessageID: UUID?
  private var sourceOwners: [UUID: UUID] = [:]
  private var requestID = UUID()
  private var searchID = UUID()
  private let history: ChatHistory

  package init(history: ChatHistory) { self.history = history }
  @discardableResult
  package func show(_ position: ConversationPageRequest.Position) async -> Bool {
    guard let repository = history.configuration.conversations, let handle = history.handle else {
      return false
    }
    let request = UUID()
    requestID = request
    isLoading = true
    failure = nil
    defer { if request == requestID { isLoading = false } }
    do {
      try await history.flush()
      guard requestID == request, history.handle == handle, !Task.isCancelled else { return false }
      let result = try await repository.page(.init(handle: handle, position: position))
      guard requestID == request, history.handle == handle, !Task.isCancelled else { return false }
      if case .around(let id) = position, !result.entries.contains(where: { $0.id == id }) {
        failure = ConversationStorageError.messageUnavailable.localizedDescription
        return false
      }
      page = result
      sourceOwners.removeAll(keepingCapacity: true)
      for entry in result.entries {
        for source in entry.message.sources where sourceOwners[source.id] == nil {
          sourceOwners[source.id] = entry.id
        }
      }
      if case .around(let id) = position {
        focusedMessageID = id
      } else {
        focusedMessageID = result.entries.first?.id
      }
      failure = nil
      return true
    } catch is CancellationError {
      return false
    } catch {
      if requestID == request, history.handle == handle, !Task.isCancelled { report(error) }
      return false
    }
  }

  package func search(_ query: String) async {
    let request = UUID()
    searchID = request
    searchedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let submittedQuery = searchedQuery
    matches = []
    failure = nil
    isSearching = false
    guard !searchedQuery.isEmpty else {
      isSearching = false
      return
    }
    guard let repository = history.configuration.conversations, let handle = history.handle else {
      return
    }
    isSearching = true
    defer { if request == searchID { isSearching = false } }
    do {
      try await history.flush()
      guard !Task.isCancelled, handle == history.handle, searchID == request else { return }
      let found = try await repository.search(
        .init(companionID: handle.companionID, query: submittedQuery))
      guard !Task.isCancelled, handle == history.handle, searchID == request else { return }
      matches = found
      failure = nil
    } catch is CancellationError {
      return
    } catch {
      if !Task.isCancelled, handle == history.handle, searchID == request { report(error) }
    }
  }

  package func cancelSearch() {
    searchID = UUID()
    isSearching = false
    matches = []
    searchedQuery = ""
  }

  package func cancelNavigation() {
    requestID = UUID()
    isLoading = false
  }

  package func showLatest() {
    resetPage()
    rememberPosition(nil)
  }

  package func reset() {
    resetPage()
    cancelSearch()
    failure = nil
  }

  private func resetPage() {
    cancelNavigation()
    page = nil
    focusedMessageID = nil
    isLoading = false
    sourceOwners.removeAll(keepingCapacity: true)
  }

  package func sourceCards(for message: ChatMessage) -> [ChatSource] {
    message.sources.filter { sourceOwners[$0.id] == message.id }
  }

  package func rememberPosition(_ id: UUID?) {
    var checkpoint = history.checkpoint
    checkpoint.readingMessageID = id
    history.update(checkpoint)
  }

  private func report(_ error: Error) {
    failure = error.localizedDescription
    fputs("Conversation browsing failed: \(error)\n", stderr)
  }
}
