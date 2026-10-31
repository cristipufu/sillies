import Foundation
import Observation
import SilliesCore
import SilliesPersistence
import SilliesVault

/// Owns vault browsing and commands. Views render state and forward user intentions.
@MainActor @Observable
final class SessionVaultModel {
  private static let searchDebounce: Duration = .milliseconds(120)
  private static let feedbackDuration: Duration = .milliseconds(1800)
  private let vault: SessionVaultStore
  @ObservationIgnored private let loadDetail: @MainActor (UUID) async throws -> SessionRecord?
  var selectedFilter: CompanionSkillKind?
  var searchQuery = ""
  var selectedRecordID: UUID?
  private(set) var lastStashID: UUID?
  private(set) var feedback: String?
  @ObservationIgnored private var feedbackTask: Task<Void, Never>?
  @ObservationIgnored private var feedbackGeneration = UUID()
  @ObservationIgnored private let exporter: VaultExportController
  @ObservationIgnored private let speakerWorker = SessionSpeakerWorker()
  @ObservationIgnored private var speakerTask: Task<Void, Never>?
  @ObservationIgnored private let transcriptWindow = SavedTranscriptWindow()
  let pasteBack: PasteBackCoordinator?
  private var listing: VaultListing
  var filteredRecords: [SessionRecordHeader] { listing.records }
  private(set) var detail: SessionRecord?
  private(set) var detailError: String?
  private(set) var isLoadingDetail = false
  private var detailGeneration = UUID()
  private var detailRevision = 0
  @ObservationIgnored private var observedDetailRevision: Int?
  private var isPresented = true
  private(set) var isSearching = false
  private(set) var searchError: String?
  private var searchGeneration = UUID()
  private var pageRequest = 0
  private var appliedSearch: SearchIdentity?
  struct SearchIdentity: Hashable {
    let revision: Int
    let kind: CompanionSkillKind?
    let query: String
    let pageRequest: Int
    var search: SessionRecordSearch { .init(kind: kind, query: query) }
    func hasSameFilter(as other: Self?) -> Bool {
      kind == other?.kind && search.query == other?.search.query
    }
  }
  struct DetailIdentity: Hashable {
    let id: UUID?
    let revision: Int
  }
  var searchIdentity: SearchIdentity {
    .init(
      revision: vault.searchRevision, kind: selectedFilter, query: searchQuery,
      pageRequest: pageRequest)
  }
  var detailIdentity: DetailIdentity {
    .init(id: selectedRecordID, revision: detailRevision)
  }
  var visibleDetail: SessionRecord? { detail?.id == selectedRecordID ? detail : nil }

  init(
    vault: SessionVaultStore, initialRecordID: UUID? = nil, pasteBack: PasteBackCoordinator? = nil,
    loadDetail: (@MainActor (UUID) async throws -> SessionRecord?)? = nil
  ) {
    self.vault = vault
    self.loadDetail = loadDetail ?? { try await vault.record(id: $0) }
    exporter = VaultExportController(library: vault.library)
    listing = VaultListing(.init(records: vault.records, total: vault.recordCount, nextCursor: nil))
    self.pasteBack = pasteBack
    selectedRecordID = initialRecordID ?? vault.records.first?.id
  }

  var hasMoreResults: Bool { listing.hasMore }
  func showMore() {
    guard hasMoreResults, !isSearching else { return }
    pageRequest += 1
  }

  func refreshSearch() async {
    isPresented = true
    let token = UUID()
    searchGeneration = token
    let request = searchIdentity
    refreshDetailRevision(at: request.revision)
    isSearching = true
    defer { if searchGeneration == token { isSearching = false } }
    do {
      let updated = try await refreshedListing(for: request)
      guard !Task.isCancelled, searchGeneration == token, isPresented else { return }
      apply(updated, for: request)
    } catch {
      guard !Task.isCancelled, searchGeneration == token, isPresented else { return }
      searchError = "Could not load the Vault: \(error.localizedDescription)"
      fputs("Vault query failed: \(error)\n", stderr)
    }
  }

  private func refreshedListing(for request: SearchIdentity) async throws -> VaultListing {
    if !request.hasSameFilter(as: appliedSearch) {
      if !request.search.query.isEmpty { try await Task.sleep(for: Self.searchDebounce) }
      return VaultListing(try await vault.page(.init(search: request.search)))
    }
    let changes = appliedSearch.map { vault.changes.changes(since: $0.revision) } ?? .reload
    guard case .records(let ids) = changes else {
      return VaultListing(try await vault.page(.init(search: request.search)))
    }
    var updated = listing
    if !ids.isEmpty {
      let matches = try await vault.matchingHeaders(ids, search: request.search)
      updated.refresh(matches, changedIDs: ids)
    }
    if request.pageRequest != appliedSearch?.pageRequest, let cursor = updated.nextCursor {
      updated.append(try await vault.page(.init(search: request.search, after: cursor)))
    }
    return updated
  }

  private func apply(_ updated: VaultListing, for request: SearchIdentity) {
    let filterChanged = !request.hasSameFilter(as: appliedSearch)
    listing = updated
    appliedSearch = request
    if selectedRecordID == nil
      || (filterChanged && !filteredRecords.contains(where: { $0.id == selectedRecordID }))
    {
      selectedRecordID = filteredRecords.first?.id
    }
    searchError = nil
  }

  private func refreshDetailRevision(at revision: Int) {
    let changes = observedDetailRevision.map { vault.changes.changes(since: $0) } ?? .reload
    switch changes {
    case .reload: detailRevision = revision
    case .records(let ids):
      if let selectedRecordID, ids.contains(selectedRecordID) { detailRevision = revision }
    }
    observedDetailRevision = revision
  }

  func loadSelection() async {
    isPresented = true
    let token = UUID()
    detailGeneration = token
    guard let id = selectedRecordID else {
      detail = nil
      detailError = nil
      isLoadingDetail = false
      return
    }
    if detail?.id != id { detail = nil }
    isLoadingDetail = true
    detailError = nil
    do {
      let record = try await loadDetail(id)
      guard !Task.isCancelled, detailGeneration == token, selectedRecordID == id, isPresented else {
        return
      }
      detail = record
      if let record { vault.pin(record) }
      if record == nil { selectedRecordID = filteredRecords.first(where: { $0.id != id })?.id }
    } catch {
      guard !Task.isCancelled, detailGeneration == token, isPresented else { return }
      detailError = "Could not open this session: \(error.localizedDescription)"
      fputs("Vault detail failed: \(error)\n", stderr)
    }
    isLoadingDetail = false
  }

  func selectedHeader(in records: [SessionRecordHeader]) -> SessionRecordHeader? {
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
    delete(id: id)
    lastStashID = nil
  }

  func delete(_ record: SessionRecord) { delete(id: record.id) }
  private func delete(id: UUID) {
    if selectedRecordID == id, let index = filteredRecords.firstIndex(where: { $0.id == id }) {
      let remaining = filteredRecords.filter { $0.id != id }
      selectedRecordID = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
    }
    listing.remove(id)
    if detail?.id == id { detail = nil }
    if lastStashID == id {
      lastStashID = nil
      clearFeedback()
    }
    vault.remove(id: id)
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
    performEdit(record.id, .protection(record.isProtected ? .unprotected : .protected))
  }
  func export(_ records: [SessionRecord]) {
    exportSelection(.records(records.map(\.id)))
  }
  func exportAll() { exportSelection(.all) }
  private func exportSelection(_ selection: VaultExportSelection) {
    vault.whenPersisted { [weak self] error in
      guard let self, self.isPresented else { return }
      if let error {
        self.showFeedback(error)
        return
      }
      self.exporter.chooseFolder(selection) { [weak self] in self?.showFeedback($0) }
    }
  }
  func openTranscript(_ record: SessionRecord) {
    transcriptWindow.show(record.transcript, title: record.displayTitle)
  }
  func regenerateNotes(_ record: SessionRecord) {
    performEdit(
      record.id, .requestNotes, feedback: "Refreshing notes with your selected local model")
  }

  func rename(_ speaker: SessionSpeakerIdentity, to name: String, in record: SessionRecord) {
    let id = record.id
    speakerTask = Task { [weak self, speakerWorker, preceding = speakerTask] in
      await preceding?.value
      do {
        guard let self, let latest = try await self.vault.record(id: id) else {
          return
        }
        let updated = await speakerWorker.rename(speaker, to: name, in: latest)
        guard
          try await self.vault.edit(
            id: id, .renameSpeaker(.init(original: latest, renamed: updated)))
        else {
          self.showFeedback("This session changed. Try renaming the speaker again.")
          return
        }
        self.showFeedback("Speaker updated · Refreshing notes")
      } catch {
        fputs("Could not rename the speaker: \(error)\n", stderr)
        self?.showFeedback("Could not update the speaker: \(error.localizedDescription)")
      }
    }
  }
  func retryScreenshotText(_ id: UUID) { performEdit(id, .retryScreenshot) }
  private func performEdit(_ id: UUID, _ command: VaultRecordEdit, feedback: String? = nil) {
    vault.submitEdit(id: id, command) { [weak self] result in
      switch result {
      case .success(true): if let feedback { self?.showFeedback(feedback) }
      case .success(false): break
      case .failure(let error):
        fputs("Vault edit failed: \(error)\n", stderr)
        self?.showFeedback("Could not update this session: \(error.localizedDescription)")
      }
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
    isPresented = false
    detailGeneration = UUID()
    searchGeneration = UUID()
    isSearching = false
    detail = nil
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
    guard isPresented else { return }
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
