import Foundation
import Observation
import SilliesCore

/// One small explicit selection. Record bodies are resolved by the injected background provider.
@MainActor @Observable package final class ChatSelectedRecords {
  package private(set) var selection = ConversationRecordSelection()
  package private(set) var records: [ConversationRecordContext] = []
  package private(set) var failure: String?
  package private(set) var isLoading = false
  package var canChange: @MainActor () -> Bool = { true }
  package var onChange: (@MainActor () -> Void)?
  private let provider: (any ConversationMaterialProviding)?
  @ObservationIgnored private var task: Task<Void, Never>?
  private var generation = UUID()
  package var isAvailable: Bool { provider != nil }
  package var canAdd: Bool {
    isAvailable && canChange() && selection.ids.count < ConversationRecordSelection.maximumRecords
  }

  package init(provider: (any ConversationMaterialProviding)?) { self.provider = provider }

  package func restore(_ selection: ConversationRecordSelection) {
    self.selection = selection
    records = []
    failure = nil
    refresh()
  }

  @discardableResult package func add(_ id: UUID) -> Bool {
    guard isAvailable, canChange() else {
      failure = String(
        localized: "Wait for the current reply or stop Talk before adding a Vault item.")
      return false
    }
    do {
      try selection.add(id)
      failure = nil
      onChange?()
      refresh()
      return true
    } catch {
      failure = error.localizedDescription
      return false
    }
  }

  package func remove(_ id: UUID) {
    guard canChange() else { return }
    selection.remove(id)
    records.removeAll { $0.id == id }
    failure = nil
    onChange?()
    refresh()
  }

  package func refresh() {
    stop()
    guard let provider, !selection.ids.isEmpty else {
      records = []
      return
    }
    let token = generation
    let selected = selection
    isLoading = true
    task = Task { [weak self] in
      do {
        let records = try await provider.selectedRecords(selected, query: "")
        try Task.checkCancellation()
        guard let self, self.generation == token else { return }
        self.records = records
        self.failure = nil
      } catch is CancellationError {
      } catch {
        guard let self, self.generation == token else { return }
        self.failure = error.localizedDescription
      }
      guard let self, self.generation == token else { return }
      self.task = nil
      self.isLoading = false
    }
  }

  package func stop() {
    generation = UUID()
    task?.cancel()
    task = nil
    isLoading = false
  }
}
