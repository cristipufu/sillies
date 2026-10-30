import Foundation
import Observation
import SilliesCore

/// Owns vault browsing and commands. Views render state and forward user intentions.
@MainActor @Observable
final class SessionVaultModel {
  private static let feedbackDuration: Duration = .milliseconds(1800)
  private let vault: SessionVaultStore
  var selectedFilter: CompanionSkillKind?
  var searchQuery = ""
  var selectedRecordID: UUID?
  private(set) var lastStashID: UUID?
  private(set) var feedback: String?
  @ObservationIgnored private var feedbackTask: Task<Void, Never>?
  @ObservationIgnored private var feedbackGeneration = UUID()

  init(vault: SessionVaultStore, initialRecordID: UUID? = nil) {
    self.vault = vault
    selectedRecordID = initialRecordID ?? vault.records.first?.id
  }

  var filteredRecords: [SessionRecord] {
    let search = SessionRecordSearch(kind: selectedFilter, query: searchQuery)
    return vault.records.filter(search.matches)
  }

  func selectedRecord(in records: [SessionRecord]) -> SessionRecord? {
    records.first { $0.id == selectedRecordID } ?? records.first
  }

  func saveStash(_ items: [String]) {
    guard let contents = StashContents(items) else {
      showFeedback("Copy text or a link first")
      return
    }
    let record = SessionRecord(
      kind: .stash,
      origin: .init(
        characterID: "workspace", characterName: "Sillies", source: .init(appName: "Pocket Stash")),
      content: .init(
        text: .init(stashedItems: contents.items), notes: .init(summary: contents.summary)))
    vault.add(record)
    selectedFilter = .stash
    searchQuery = ""
    selectedRecordID = record.id
    lastStashID = record.id
    showFeedback("Saving…")
    let generation = feedbackGeneration
    vault.whenPersisted { [weak self] error in
      guard let self, self.feedbackGeneration == generation else { return }
      self.showFeedback(error == nil ? "Saved to Pocket Stash" : "Could not save — see details")
    }
  }

  func undoStash() {
    guard let id = lastStashID else { return }
    if let record = vault.records.first(where: { $0.id == id }) { delete(record) }
    lastStashID = nil
  }

  func delete(_ record: SessionRecord) {
    let records = filteredRecords
    if selectedRecord(in: records)?.id == record.id,
      let index = records.firstIndex(where: { $0.id == record.id })
    {
      let remaining = records.filter { $0.id != record.id }
      selectedRecordID = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
    }
    if lastStashID == record.id {
      lastStashID = nil
      clearFeedback()
    }
    vault.remove(id: record.id)
  }

  func copyText(_ text: String, feedback message: String) {
    vault.copyText(text)
    showFeedback(message)
  }

  func copyImage(for record: SessionRecord) {
    vault.copyImage(for: record)
    showFeedback("Image copied")
  }

  func stop() {
    clearFeedback()
    vault.setPinnedRecord(nil)
  }

  private func clearFeedback() {
    feedbackGeneration = UUID()
    feedbackTask?.cancel()
    feedbackTask = nil
    feedback = nil
  }

  private func showFeedback(_ message: String) {
    feedbackTask?.cancel()
    feedbackGeneration = UUID()
    feedback = message
    feedbackTask = Task { [weak self] in
      do { try await Task.sleep(for: Self.feedbackDuration) } catch { return }
      guard !Task.isCancelled else { return }
      self?.feedback = nil
      self?.feedbackTask = nil
    }
  }
}
