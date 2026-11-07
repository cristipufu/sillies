import Foundation
import Observation
import SilliesCore
import SilliesVault

/// A single bounded editing surface. Saves are serialized and drafts survive conflicts and restarts.
@MainActor @Observable final class VaultTextEditorModel {
  private static let saveDelay: Duration = .milliseconds(450)
  private let vault: SessionVaultStore
  @ObservationIgnored let readingState = VaultEditorReadingState()
  struct FormattingRequest {
    let id = UUID()
    let action: VaultTextFormatting
  }
  private(set) var formattingRequest: FormattingRequest?
  private(set) var location: VaultBlockLocation?
  private(set) var revision: UUID?
  private(set) var blocks: [VaultContentBlock] = []
  private(set) var nextOrdinal: Int?
  private(set) var previousOrdinal: Int?
  private(set) var text = ""
  private(set) var isLoading = false
  private(set) var isSaving = false
  private(set) var isRecovering = false
  private(set) var isDirty = false
  private(set) var recoveredDraft = false
  private(set) var error: String?
  private(set) var identity = UUID()
  private(set) var recoverySaved = false
  private(set) var selection = NSRange(location: 0, length: 0)
  struct RevealRequest {
    let id = UUID()
    let range: NSRange
  }
  private(set) var revealRequest: RevealRequest?
  func reveal(_ location: VaultBlockLocation) {
    var offset = 0
    for block in blocks {
      if block.location == location {
        revealRequest = .init(range: NSRange(location: offset, length: 0))
        return
      }
      offset += (block.text as NSString).length
    }
  }
  @ObservationIgnored var onInteraction: (() -> Void)?
  var selectedText: String {
    let value = text as NSString
    guard VaultTextRange.contains(selection, inLength: value.length)
    else { return "" }
    return value.substring(with: selection)
  }
  func selectText(_ range: NSRange) {
    selection =
      VaultTextRange.contains(range, inLength: (text as NSString).length)
      ? range : NSRange(location: 0, length: 0)
    onInteraction?()
  }
  func quotedSelection(title: String) throws -> VaultQuotedPassage? {
    guard !selectedText.isEmpty else { return nil }
    var offset = 0
    let source = blocks.first { block in
      offset += (block.text as NSString).length
      return selection.location < offset
    }
    guard let source else { return nil }
    return try .init(reference: .init(block: source), title: title, text: selectedText)
  }
  var canNavigate: Bool { !isDirty || recoverySaved }
  private var range = 0..<0
  private var change = UUID()
  private var request = UUID()
  @ObservationIgnored private var delayedSave: Task<Void, Never>?
  @ObservationIgnored private var saveCompletions: [@MainActor () -> Void] = []
  @ObservationIgnored private var flusherID: UUID?
  var isEditable: Bool {
    location.map { [.notes, .transcript, .screenshotText].contains($0.section) } ?? false
  }
  var canAcceptEdits: Bool { isEditable && !isLoading && !isRecovering }

  init(vault: SessionVaultStore) {
    self.vault = vault
    flusherID = vault.registerDraftFlusher { [weak self] completion in
      guard let self else {
        completion()
        return
      }
      self.flush(completion: completion)
    }
  }

  func load(_ location: VaultBlockLocation) async {
    let token = UUID()
    request = token
    isLoading = true
    defer { if token == request { isLoading = false } }
    await flush()
    guard token == request, !Task.isCancelled, canNavigate else { return }
    do {
      try await vault.library.prepareDocument(id: location.recordID)
      let draft = try await vault.library.draft(location)
      let displayed = draft?.location ?? location
      let page = try await vault.library.sectionPage(displayed)
      let revision = try await vault.library.sectionRevision(displayed)
      guard token == request, !Task.isCancelled else { return }
      self.location = displayed
      self.revision = revision
      blocks = page.blocks
      nextOrdinal = page.nextOrdinal
      previousOrdinal = page.previousOrdinal
      range = displayed.ordinal..<(displayed.ordinal + page.blocks.count)
      text = page.blocks.map(\.text).joined()
      selection = NSRange(location: 0, length: 0)
      revealRequest = nil
      formattingRequest = nil
      isDirty = false
      error = nil
      recoveredDraft = draft != nil
      recoverySaved = draft != nil
      if let draft {
        self.location = draft.location
        self.revision = draft.expectedRevision
        range = draft.blockRange
        text = draft.text
        isDirty = true
        // Do not offer navigation into the middle of a larger recovered edit.
        nextOrdinal = page.nextOrdinal.map { max($0, draft.blockRange.upperBound) }
      }
      identity = UUID()
    } catch is CancellationError { return } catch {
      guard token == request, !Task.isCancelled else { return }
      self.error = error.localizedDescription
    }
  }

  func replaceText(_ value: String) {
    guard canAcceptEdits, value != text else { return }
    text = value
    onInteraction?()
    change = UUID()
    isDirty = true
    recoverySaved = false
    cancelScheduledSave()
    delayedSave = Task { [weak self] in
      do { try await Task.sleep(for: Self.saveDelay) } catch { return }
      await self?.flush()
    }
  }

  func format(_ action: VaultTextFormatting) {
    guard canAcceptEdits else { return }
    formattingRequest = .init(action: action)
  }

  func reportEditLimit() {
    error = String(
      localized: "This page is full. Add a new note for more text; your existing text is safe.")
  }

  func flush() async {
    await withCheckedContinuation { continuation in flush { continuation.resume() } }
  }

  func flush(completion: @escaping @MainActor () -> Void) {
    cancelScheduledSave()
    saveCompletions.append(completion)
    guard !isSaving else { return }
    savePendingChanges()
  }

  private func savePendingChanges() {
    guard isDirty, isEditable, let location else {
      finishSaving()
      return
    }
    guard error == nil || !recoverySaved else {
      finishSaving()
      return
    }
    isSaving = true
    let version = change
    let draft = VaultDraft(location: location, revision: revision, range: range, text: text)
    Task.detached { [self, library = vault.library] in
      var persisted = false
      let result: Result<VaultDraftCommit, Error>
      do {
        try await library.saveDraft(draft)
        persisted = true
        result = .success(try await library.commitDraft(draft, at: Date()))
      } catch { result = .failure(error) }
      let hasRecovery = persisted
      MainRunLoopDelivery.perform {
        self.receive(result, draft: draft, version: version, hasRecovery: hasRecovery)
      }
    }
  }

  private func receive(
    _ result: Result<VaultDraftCommit, Error>, draft: VaultDraft, version: UUID, hasRecovery: Bool
  ) {
    isSaving = false
    switch result {
    case .success(let saved):
      if let flusherID { vault.reportDraftFailure(nil, owner: flusherID) }
      revision = saved.revision
      blocks = saved.blocks
      let count = saved.blocks.count
      let delta = count - range.count
      range = range.lowerBound..<(range.lowerBound + count)
      nextOrdinal = nextOrdinal.map { $0 + delta }
      if version == change { isDirty = false }
      recoveredDraft = false
      recoverySaved = !isDirty
      error = nil
      vault.workspaceChanged([draft.location.recordID])
      savePendingChanges()
    case .failure(let failure):
      recoverySaved = hasRecovery && version == change
      recoveredDraft = recoverySaved
      error = failure.localizedDescription
      if let flusherID { vault.reportDraftFailure(recoverySaved ? nil : error, owner: flusherID) }
      fputs("Vault draft save failed: \(failure)\n", stderr)
      finishSaving()
    }
  }

  private func finishSaving() {
    isSaving = false
    let completions = saveCompletions
    saveCompletions.removeAll()
    for completion in completions { completion() }
  }

  func discardRecoveredDraft() async {
    guard let location, !isRecovering, !isSaving else { return }
    let token = request
    cancelScheduledSave()
    isRecovering = true
    defer { isRecovering = false }
    do {
      try await vault.library.discardDraft(location)
      guard request == token, !Task.isCancelled else { return }
      isDirty = false
      if let flusherID { vault.reportDraftFailure(nil, owner: flusherID) }
      await load(location)
    } catch is CancellationError { return } catch {
      guard request == token, !Task.isCancelled else { return }
      self.error = error.localizedDescription
    }
  }

  func retrySavingDraft() async {
    guard !isRecovering else { return }
    error = nil
    await flush()
  }
  func recoverAsNote() async throws -> UUID? {
    guard let location, isDirty, !isRecovering else { return nil }
    let token = request
    isRecovering = true
    defer { isRecovering = false }
    await flush()
    guard request == token, !Task.isCancelled else { return nil }
    let header = try await vault.createDocument(
      metadata: .init(kind: .note, title: String(localized: "Recovered note"), modifiedAt: Date()),
      notes: text)
    guard request == token, !Task.isCancelled else { return header.id }
    try await vault.library.discardDraft(location)
    guard request == token, !Task.isCancelled else { return header.id }
    isDirty = false
    if let flusherID { vault.reportDraftFailure(nil, owner: flusherID) }
    recoveredDraft = false
    error = nil
    return header.id
  }

  func move(to ordinal: Int) async {
    guard let location else { return }
    await load(.init(recordID: location.recordID, section: location.section, ordinal: ordinal))
  }

  func stop() {
    request = UUID()
    isLoading = false
    flush {}
  }
  private func cancelScheduledSave() {
    delayedSave?.cancel()
    delayedSave = nil
  }
  isolated deinit {
    if let flusherID { vault.unregisterDraftFlusher(flusherID) }
    delayedSave?.cancel()
  }
}
