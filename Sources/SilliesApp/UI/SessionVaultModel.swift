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
  let workspace: VaultWorkspaceModel
  @ObservationIgnored private let loadDetail: @MainActor (UUID) async throws -> SessionRecord?
  var selectedFilter: CompanionSkillKind? {
    didSet { if selectedFilter != oldValue { requestedRecordID = nil } }
  }
  var searchQuery = "" {
    didSet { if searchQuery != oldValue { requestedRecordID = nil } }
  }
  var selectedRecordID: UUID? {
    didSet {
      if selectedRecordID != oldValue {
        expandedTranscriptID = nil
        requestedRecordID = nil
      }
    }
  }
  private var requestedRecordID: UUID?
  private(set) var lastStashID: UUID?
  private(set) var feedback: String?
  private(set) var keepsFeedbackVisible = false
  private(set) var discussionFailure: SessionFailure?
  @ObservationIgnored private var feedbackTask: Task<Void, Never>?
  @ObservationIgnored private var feedbackGeneration = UUID()
  @ObservationIgnored private let windowActions: VaultWindowActions?
  private var exportRequest: UUID?
  private var fileCancellationRequest: UUID?
  private var discussionRequest: UUID?
  private var transcriptRequest: UUID?
  private var relinkRequest: UUID?
  private var pasteRequest: UUID?
  @ObservationIgnored private var pasteTask: Task<Void, Never>?
  var isExporting: Bool { exportRequest != nil || fileCancellationRequest != nil }
  var isPasting: Bool { pasteRequest != nil }
  private(set) var fileOperationTitle = String(localized: "Saving your export…")
  private(set) var expandedTranscriptID: UUID?
  @ObservationIgnored private let speakerWorker = SessionSpeakerWorker()
  @ObservationIgnored private var speakerTask: Task<Void, Never>?
  let pasteBack: PasteBackCoordinator?
  let discussion: VaultDiscussionPresentation?
  private var listing: VaultListing
  private(set) var relatedRecords: [SessionRecordHeader] = []
  var keywordRecords: [SessionRecordHeader] { listing.records }
  var filteredRecords: [SessionRecordHeader] { listing.records + relatedRecords }
  private(set) var detail: SessionRecord?
  private(set) var detailError: String?
  private(set) var isLoadingDetail = false
  private var detailGeneration = UUID()
  private var detailRevision = 0
  @ObservationIgnored private var observedDetailRevision: Int?
  private(set) var isPresented = true
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

  @MainActor struct Presentation {
    var initialRecordID: UUID?
    var pasteBack: PasteBackCoordinator?
    var windowActions: VaultWindowActions? = nil
    var discussion: VaultDiscussionPresentation? = nil
  }
  init(
    vault: SessionVaultStore, presentation: Presentation,
    loadDetail: (@MainActor (UUID) async throws -> SessionRecord?)? = nil
  ) {
    windowActions = presentation.windowActions
    self.vault = vault
    workspace = VaultWorkspaceModel(vault: vault)
    self.loadDetail = loadDetail ?? { try await vault.record(id: $0) }
    listing = VaultListing(.init(records: vault.records, total: vault.recordCount, nextCursor: nil))
    self.pasteBack = presentation.pasteBack
    discussion = presentation.discussion
    selectedRecordID = presentation.initialRecordID ?? vault.records.first?.id
    requestedRecordID = presentation.initialRecordID
  }

  var hasMoreResults: Bool { listing.hasMore }
  var canExport: Bool { isPresented && windowActions != nil && !isExporting }
  var canPopOutTranscript: Bool { windowActions != nil }
  var canCancelFileOperation: Bool {
    exportRequest != nil && windowActions?.cancelFileOperation != nil
  }

  func cancelFileOperation() {
    guard canCancelFileOperation, let cancel = windowActions?.cancelFileOperation else { return }
    let request = UUID()
    fileCancellationRequest = request
    exportRequest = nil
    fileOperationTitle = String(localized: "Cancelling…")
    cancel { [weak self] in
      guard let self, fileCancellationRequest == request else { return }
      fileCancellationRequest = nil
    }
  }
  func dismissFeedback() { clearFeedback() }

  func navigate(to recordID: UUID) {
    selectedFilter = nil
    searchQuery = ""
    selectedRecordID = recordID
    requestedRecordID = recordID
    expandedTranscriptID = nil
  }

  func resume() {
    isPresented = true
    workspace.resume()
  }
  func showMore() {
    guard hasMoreResults, !isSearching else { return }
    pageRequest += 1
  }

  func refreshSearch() async {
    guard isPresented else { return }
    let token = UUID()
    searchGeneration = token
    let request = searchIdentity
    refreshDetailRevision(at: request.revision)
    isSearching = true
    defer { if searchGeneration == token { isSearching = false } }
    do {
      let updated = try await refreshedListing(for: request)
      let related = try await relatedRecords(
        for: request, excluding: Set(updated.records.map(\.id)))
      guard !Task.isCancelled, searchGeneration == token, searchIdentity == request, isPresented
      else { return }
      relatedRecords = related
      apply(updated, for: request)
    } catch {
      guard !Task.isCancelled, searchGeneration == token, isPresented else { return }
      searchError = String(localized: "Could not load the Vault: \(error.localizedDescription)")
      fputs("Vault query failed: \(error)\n", stderr)
    }
  }

  private func relatedRecords(for request: SearchIdentity, excluding ids: Set<UUID>) async throws
    -> [SessionRecordHeader]
  {
    guard !request.search.query.isEmpty else { return [] }
    let category: VaultSearchRequest.Category
    switch request.kind {
    case .listen, .participate, .record: category = .meetings
    case .snap, .explain: category = .screenshots
    case .stash: category = .stash
    default: category = .all
    }
    return try await vault.library.relatedMatches(.init(query: request.query, category: category))
      .map(\.header).filter {
        !ids.contains($0.id) && (request.kind == nil || $0.kind == request.kind)
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
      || (filterChanged && requestedRecordID != selectedRecordID
        && !filteredRecords.contains(where: { $0.id == selectedRecordID }))
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
    guard isPresented else { return }
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
      if record == nil {
        if requestedRecordID == id {
          detailError = String(localized: "Unavailable Vault item")
        } else {
          selectedRecordID = filteredRecords.first(where: { $0.id != id })?.id
        }
      }
    } catch {
      guard !Task.isCancelled, detailGeneration == token, isPresented else { return }
      detailError = String(localized: "Could not open this session: \(error.localizedDescription)")
      fputs("Vault detail failed: \(error)\n", stderr)
    }
    isLoadingDetail = false
  }

  func selectedHeader(in records: [SessionRecordHeader]) -> SessionRecordHeader? {
    records.first { $0.id == selectedRecordID }
  }

  func saveStash(_ items: [String]) {
    guard let contents = StashContents(items) else {
      showFeedback(String(localized: "Copy text or a link first"))
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
    showFeedback(String(localized: "Saving…"))
    let generation = feedbackGeneration
    vault.whenPersisted { [weak self] error in
      guard let self, self.feedbackGeneration == generation else { return }
      self.showFeedback(
        error == nil
          ? String(localized: "Saved to Pocket Stash")
          : String(localized: "Could not save — see details"))
    }
  }

  func undoStash() {
    guard let id = lastStashID else { return }
    delete(id: id)
    lastStashID = nil
  }

  func delete(_ record: SessionRecord) { delete(id: record.id) }
  private func delete(id: UUID) {
    if selectedRecordID == id {
      let index = filteredRecords.firstIndex(where: { $0.id == id }) ?? 0
      let remaining = filteredRecords.filter { $0.id != id }
      selectedRecordID = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
    }
    listing.remove(id)
    relatedRecords.removeAll { $0.id == id }
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
    showFeedback(String(localized: "Image copied"))
  }

  func toggleProtection(_ record: SessionRecord) {
    performEdit(record.id, .protection(record.isProtected ? .unprotected : .protected))
  }
  func removeProtection(id: UUID) { performEdit(id, .protection(.unprotected)) }
  func keep(id: UUID) { performEdit(id, .protection(.protected)) }
  func relink(_ reference: VaultFileReference) {
    guard isPresented, relinkRequest == nil, let relink = windowActions?.relink else { return }
    let request = UUID()
    relinkRequest = request
    relink(reference) { [weak self] message in
      guard let self, relinkRequest == request else { return }
      relinkRequest = nil
      guard isPresented, let message else { return }
      showPersistentFeedback(message)
      vault.workspaceChanged([reference.recordID])
      if workspace.document.header?.id == reference.recordID {
        Task { await self.workspace.document.externalFiles.load(id: reference.recordID) }
      }
    }
  }
  func export(_ records: [SessionRecord]) {
    exportSelection(.records(records.map(\.id)))
  }
  func exportIDs(_ ids: [UUID]) { exportSelection(.records(ids)) }
  func exportSelectedText() {
    let text = workspace.document.editor.selectedText
    guard !text.isEmpty, let export = windowActions?.exportText else { return }
    beginExport { completion in export(text, completion) }
  }
  func exportAll() { exportSelection(.all) }
  func backup() {
    guard let backup = windowActions?.backup else { return }
    beginExport(backup)
  }
  func prepareRestore() {
    guard let prepare = windowActions?.prepareRestore,
      let request = beginFileOperation(
        title: String(localized: "Preparing your backup for restoration…"))
    else { return }
    // Recovery remains available when the current archive cannot be flushed or opened.
    performFileOperation(prepare, request: request)
  }
  private func exportSelection(_ selection: VaultExportSelection) {
    guard let windowActions, canExport else { return }
    beginExport { completion in windowActions.export(selection, completion) }
  }
  private func beginExport(_ action: @escaping (@escaping (String?) -> Void) -> Void) {
    guard let request = beginFileOperation(title: String(localized: "Saving your export…")) else {
      return
    }
    vault.whenPersisted { [weak self] error in
      guard let self, self.isPresented, self.exportRequest == request else { return }
      if let error {
        self.exportRequest = nil
        self.showPersistentFeedback(error)
        return
      }
      performFileOperation(action, request: request)
    }
  }
  private func beginFileOperation(title: String) -> UUID? {
    guard canExport else { return nil }
    fileOperationTitle = title
    let request = UUID()
    exportRequest = request
    return request
  }
  private func performFileOperation(_ action: (@escaping (String?) -> Void) -> Void, request: UUID)
  {
    action { [weak self] message in
      guard let self, exportRequest == request else { return }
      exportRequest = nil
      if isPresented, let message { showPersistentFeedback(message) }
    }
  }
  func openTranscript(_ record: SessionRecord) {
    expandedTranscriptID = record.id
  }
  func closeTranscript() { expandedTranscriptID = nil }
  func popOutTranscript(_ record: SessionRecord) { windowActions?.popOutTranscript(record) }
  func popOutTranscript(id: UUID) async {
    guard isPresented else { return }
    let request = UUID()
    transcriptRequest = request
    defer { if transcriptRequest == request { transcriptRequest = nil } }
    do {
      guard let record = try await loadDetail(id), transcriptRequest == request,
        isPresented, !Task.isCancelled
      else {
        return
      }
      popOutTranscript(record)
    } catch {
      guard transcriptRequest == request, isPresented, !Task.isCancelled else { return }
      showPersistentFeedback(error.localizedDescription)
    }
  }
  func discuss(_ recordID: UUID, with companion: ConversationOwner) {
    guard let discussion, isPresented, discussionRequest == nil else { return }
    let request = UUID()
    discussionRequest = request
    discussionFailure = nil
    vault.whenPersisted { [weak self] error in
      guard let self, self.isPresented, self.discussionRequest == request else { return }
      self.discussionRequest = nil
      if let error {
        self.discussionFailure = .init(category: .recordingSave, message: error)
        return
      }
      if let failure = discussion.open(recordID, companion) {
        self.discussionFailure = failure
      }
    }
  }
  func dismissDiscussionFailure() { discussionFailure = nil }
  func regenerateNotes(_ record: SessionRecord) {
    regenerateNotes(id: record.id)
  }

  func regenerateNotes(id: UUID) {
    performEdit(
      id, .requestNotes,
      feedback: String(localized: "Refreshing notes with your selected local model"))
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
          self.showFeedback(
            String(localized: "This session changed. Try renaming the speaker again."))
          return
        }
        self.showFeedback(String(localized: "Speaker updated · Refreshing notes"))
      } catch {
        fputs("Could not rename the speaker: \(error)\n", stderr)
        self?.showPersistentFeedback(
          String(localized: "Could not update the speaker: \(error.localizedDescription)"))
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
        self?.showPersistentFeedback(
          String(localized: "Could not update this session: \(error.localizedDescription)"))
      }
    }
  }
  func paste(id: UUID) {
    guard isPresented, pasteRequest == nil, let pasteBack else { return }
    let request = UUID()
    let destinationID = pasteBack.destination?.id
    pasteRequest = request
    pasteTask = Task { [weak self] in
      guard let self else { return }
      defer {
        if pasteRequest == request {
          pasteRequest = nil
          pasteTask = nil
        }
      }
      do {
        await workspace.document.flush()
        guard pasteRequest == request, isPresented, workspace.document.canNavigate,
          !Task.isCancelled
        else { return }
        let record = try await loadDetail(id)
        guard pasteRequest == request, isPresented, pasteBack.destination?.id == destinationID,
          !Task.isCancelled
        else { return }
        guard let record else {
          throw VaultStorageError(message: String(localized: "Unavailable Vault item"))
        }
        guard !record.primaryText.isEmpty else { return }
        try await pasteBack.paste(record.primaryText)
        guard pasteRequest == request, isPresented, !Task.isCancelled else { return }
        showFeedback(String(localized: "Text pasted"))
      } catch is CancellationError { return } catch {
        guard pasteRequest == request, isPresented, !Task.isCancelled else { return }
        showPersistentFeedback(error.localizedDescription)
      }
    }
  }

  func stop() {
    cancelFileOperation()
    workspace.stop()
    isPresented = false
    exportRequest = nil
    discussionRequest = nil
    transcriptRequest = nil
    relinkRequest = nil
    pasteRequest = nil
    pasteTask?.cancel()
    pasteTask = nil
    detailGeneration = UUID()
    searchGeneration = UUID()
    isSearching = false
    isLoadingDetail = false
    clearFeedback()
    if let detail, vault.pinnedRecordID == detail.id { vault.setPinnedRecord(nil) }
  }

  private func clearFeedback() {
    feedbackGeneration = UUID()
    feedbackTask?.cancel()
    feedbackTask = nil
    feedback = nil
    keepsFeedbackVisible = false
  }

  private func showPersistentFeedback(_ message: String) {
    guard isPresented else { return }
    clearFeedback()
    feedback = message
    keepsFeedbackVisible = true
  }

  private func showFeedback(_ message: String) {
    guard isPresented else { return }
    clearFeedback()
    feedback = message
    feedbackTask = Task { [weak self] in
      do { try await Task.sleep(for: Self.feedbackDuration) } catch { return }
      guard !Task.isCancelled else { return }
      self?.feedback = nil
      self?.feedbackTask = nil
    }
  }
}
