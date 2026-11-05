import Foundation
import Observation
import SilliesCore

/// Explicit user confirmation bypasses inference, not source validation or atomic persistence.
@MainActor @Observable
package final class ChatMemoryEditor {
  private struct Selection {
    let id = UUID()
    let handle: ConversationHandle
    let source: MemorySource
  }
  private let history: ChatHistory
  private var selection: Selection?
  package var topic = ""
  package var value = ""
  package private(set) var isSaving = false
  package private(set) var failure: String?
  package var isPresented: Bool { selection != nil }
  package var sourceQuote: String { selection?.source.quote ?? "" }
  package var canSave: Bool {
    selection != nil && !isSaving && fact.isValid
  }
  private var fact: MemoryFact {
    .init(
      key: topic.trimmingCharacters(in: .whitespacesAndNewlines),
      value: value.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  package init(history: ChatHistory) { self.history = history }

  package func canRemember(_ message: ChatMessage) -> Bool {
    history.isLoaded && history.handle != nil && message.role == .user
      && !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  package func begin(_ message: ChatMessage) {
    guard !isSaving, canRemember(message), let handle = history.handle else { return }
    selection = .init(handle: handle, source: .init(messageID: message.id, quote: message.text))
    topic = ""
    value = message.text
    failure = nil
  }

  package func close() {
    guard !isSaving else { return }
    clearSelection()
  }

  private func clearSelection() {
    selection = nil
    topic = ""
    value = ""
    failure = nil
  }

  package func save() async {
    guard canSave, let selected = selection else { return }
    isSaving = true
    defer { isSaving = false }
    do {
      try await history.remember(
        .init(handle: selected.handle, fact: fact, source: selected.source, savedAt: Date()))
      guard selection?.id == selected.id else { return }
      clearSelection()
    } catch {
      guard selection?.id == selected.id else { return }
      failure = error.localizedDescription
      fputs("Explicit memory save failed: \(error)\n", stderr)
    }
  }
}
