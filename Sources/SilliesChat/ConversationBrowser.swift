import Foundation
import Observation
import SilliesCore

/// Browsing never replaces the recent messages supplied to inference.
@MainActor @Observable
package final class ConversationBrowser {
  package private(set) var page: ConversationPage?
  package private(set) var matches: [ConversationSearchMatch] = []
  package private(set) var isLoading = false
  package private(set) var failure: String?
  package private(set) var focusedMessageID: UUID?
  private var sourceOwners: [UUID: UUID] = [:]
  private var requestID = UUID()
  private let history: ChatHistory

  package init(history: ChatHistory) { self.history = history }
  package func show(_ position: ConversationPageRequest.Position) async {
    guard let repository = history.configuration.conversations, let handle = history.handle else {
      return
    }
    let request = UUID()
    requestID = request
    isLoading = true
    defer { if request == requestID { isLoading = false } }
    do {
      try await history.flush()
      let result = try await repository.page(.init(handle: handle, position: position))
      guard requestID == request, history.handle == handle, !Task.isCancelled else { return }
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
    } catch {
      if requestID == request, history.handle == handle, !Task.isCancelled { report(error) }
    }
  }

  package func search(_ query: String) async {
    guard let repository = history.configuration.conversations, let handle = history.handle else {
      return
    }
    do {
      let found = try await repository.search(.init(companionID: handle.companionID, query: query))
      guard !Task.isCancelled, handle == history.handle else { return }
      matches = found
      failure = nil
    } catch { if !Task.isCancelled { report(error) } }
  }

  package func showLatest() {
    resetPage()
    rememberPosition(nil)
  }

  package func reset() {
    resetPage()
    matches = []
    failure = nil
  }

  private func resetPage() {
    requestID = UUID()
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
