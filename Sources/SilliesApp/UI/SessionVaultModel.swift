import Foundation
import Observation
import SilliesCore

/// Owns vault browsing and commands. Views render state and forward user intentions.
@MainActor @Observable
final class SessionVaultModel {
  private static let pageSize = 200
  private static let feedbackDuration: Duration = .milliseconds(1800)
  private let vault: SessionVaultStore
  var selectedFilter: CompanionSkillKind?
  var searchQuery = ""
  var selectedRecordID: UUID?
  private(set) var lastStashID: UUID?
  private(set) var feedback: String?
  @ObservationIgnored private var feedbackTask: Task<Void, Never>?
  @ObservationIgnored private var feedbackGeneration = UUID()
  @ObservationIgnored private let exporter = VaultExportController()
  @ObservationIgnored private let speakerWorker = SessionSpeakerWorker()
  @ObservationIgnored private var speakerTask: Task<Void, Never>?
  @ObservationIgnored private let transcriptWindow = SavedTranscriptWindow()
  let pasteBack: PasteBackCoordinator?
  private(set) var matchingIDs: Set<UUID> = []
  private(set) var isSearching = false
  private(set) var searchError: String?
  private var searchGeneration = UUID()
  var visibleLimit = SessionVaultModel.pageSize
  var searchIdentity: String {
    "\(vault.searchRevision):\(selectedFilter?.rawValue ?? "all"):\(searchQuery)"
  }

  init(
    vault: SessionVaultStore, initialRecordID: UUID? = nil, pasteBack: PasteBackCoordinator? = nil
  ) {
    self.vault = vault
    self.pasteBack = pasteBack
    selectedRecordID = initialRecordID ?? vault.records.first?.id
  }

  var filteredRecords: [SessionRecord] {
    Array(matchingRecords.prefix(visibleLimit))
  }
  private var matchingRecords: [SessionRecord] {
    let isQueryEmpty = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    return vault.records.filter {
      (selectedFilter == nil || $0.kind == selectedFilter)
        && (isQueryEmpty || matchingIDs.contains($0.id))
    }
  }
  var hasMoreResults: Bool { matchingRecords.count > visibleLimit }
  func showMore() { visibleLimit += Self.pageSize }

  func refreshSearch() async {
    let token = UUID()
    searchGeneration = token
    guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      isSearching = false
      matchingIDs = []
      searchError = nil
      return
    }
    isSearching = true
    do {
      try await Task.sleep(for: .milliseconds(120))
      let ids = try await vault.search(.init(kind: selectedFilter, query: searchQuery))
      guard !Task.isCancelled, searchGeneration == token else { return }
      matchingIDs = ids
      searchError = nil
    } catch {
      guard !Task.isCancelled, searchGeneration == token else { return }
      searchError = "Search is unavailable: \(error.localizedDescription)"
      fputs("Vault search failed: \(error)\n", stderr)
    }
    isSearching = false
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

  func toggleProtection(_ record: SessionRecord) {
    var updated = record
    updated.isProtected.toggle()
    vault.update(updated)
  }
  func export(_ records: [SessionRecord]) {
    exporter.chooseFolder(records: records, source: vault.storageDirectory) { [weak self] in
      self?.showFeedback($0)
    }
  }
  func exportAll() { export(vault.records) }
  func openTranscript(_ record: SessionRecord) {
    transcriptWindow.show(record.transcript, title: record.displayTitle)
  }
  func regenerateNotes(_ record: SessionRecord) {
    vault.regenerateNotes(id: record.id)
    showFeedback("Refreshing notes with your selected local model")
  }

  func rename(_ speaker: SessionSpeakerIdentity, to name: String, in record: SessionRecord) {
    speakerTask = Task { [weak self, speakerWorker, preceding = speakerTask] in
      await preceding?.value
      guard let self, let latest = self.vault.records.first(where: { $0.id == record.id }) else {
        return
      }
      let updated = await speakerWorker.rename(speaker, to: name, in: latest)
      guard var current = self.vault.records.first(where: { $0.id == record.id }),
        current.transcript == latest.transcript, current.speakerNames == latest.speakerNames
      else { return }
      current.transcript = updated.transcript
      current.speakerNames = updated.speakerNames
      current.originalSpeakerTranscript = updated.originalSpeakerTranscript
      self.vault.updateTranscript(current)
      self.showFeedback("Speaker updated · Refreshing notes")
    }
  }
  func paste(_ record: SessionRecord) {
    guard let pasteBack else { return }
    Task { [weak self] in
      do {
        try await pasteBack.paste(record.primaryText)
        self?.showFeedback("Text pasted")
      } catch { self?.showFeedback(error.localizedDescription) }
    }
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
