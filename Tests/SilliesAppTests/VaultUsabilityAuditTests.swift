import AppKit
import SilliesCore
import SilliesVault
import SwiftUI
import Testing

@testable import SilliesApp

@Test @MainActor func vaultRejectsInvalidNativeRangesBeforeCopyingOrEditing() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  await vault.waitUntilLoaded()
  vault.suspendBackgroundProcessing()
  let header = try await vault.createDocument(
    metadata: .init(kind: .note, title: "Selection", modifiedAt: Date()), notes: "Bună 🌳")
  let editor = VaultTextEditorModel(vault: vault)
  await editor.load(.init(recordID: header.id, section: .notes))
  let coordinator = VaultNativeTextEditor.Coordinator(model: editor)
  let native = NSTextView(usingTextLayoutManager: true)
  native.string = editor.text
  for range in [
    NSRange(location: -1, length: 1), NSRange(location: 0, length: -1),
    NSRange(location: NSNotFound, length: 0), NSRange(location: Int.max, length: Int.max),
    NSRange(location: 1, length: Int.max),
  ] {
    editor.selectText(range)
    #expect(editor.selectedText.isEmpty)
    #expect(!coordinator.textView(native, shouldChangeTextIn: range, replacementString: "x"))
    #expect(VaultTextRange.contains(VaultTextRange.clamped(range, toLength: 8), inLength: 8))
  }
  editor.selectText(NSRange(location: 0, length: 4))
  #expect(editor.selectedText == "Bună")
  let location = try #require(editor.location)
  editor.readingState.save(
    .init(
      selection: NSRange(location: 0, length: 0), origin: .init(x: CGFloat.nan, y: CGFloat.infinity)
    ),
    at: location)
  #expect(editor.readingState.position(at: location)?.origin == .zero)
  editor.stop()
  await vault.flush()
}

@Test @MainActor func vaultDelayedActionsCannotEditANewlySelectedDocumentOrHiddenBulkSelection()
  async throws
{
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  await vault.waitUntilLoaded()
  vault.suspendBackgroundProcessing()
  let first = try await vault.createDocument(
    metadata: .init(kind: .note, title: "First", modifiedAt: Date()), notes: "First words")
  let second = try await vault.createDocument(
    metadata: .init(kind: .note, title: "Second", modifiedAt: Date()), notes: "Second words")
  let workspace = VaultWorkspaceModel(vault: vault)
  workspace.resume()
  defer { workspace.stop() }
  await workspace.document.open(first.id)
  let delayedTrash = { await workspace.document.moveToTrash(recordID: first.id) }
  await workspace.document.open(second.id)
  await delayedTrash()
  await workspace.document.followAudio(recordID: first.id)
  #expect(!workspace.document.recording.isFollowing)
  await workspace.document.recording.open(second.id)
  await workspace.document.recording.addBookmark(seconds: 12, recordID: first.id)
  #expect(try await vault.library.recordingBookmarks(id: second.id).isEmpty)
  await workspace.document.edit(.star, recordID: first.id)
  #expect(try await vault.library.documentHeader(id: first.id)?.metadata.trashedAt == nil)
  #expect(try await vault.library.documentHeader(id: second.id)?.metadata.trashedAt == nil)
  #expect(workspace.document.header?.id == second.id && workspace.document.error == nil)
  #expect(try await vault.library.documentHeader(id: second.id)?.metadata.isStarred == false)

  await workspace.refresh()
  workspace.selectedIDs = [first.id, second.id]
  #expect(workspace.canEditSelection)
  workspace.updateSearchText("no matching phrase in this fixture")
  #expect(!workspace.canEditSelection)
  await workspace.editSelection(.moveToTrash)
  await workspace.refresh()
  #expect(workspace.selectedIDs.isEmpty && workspace.records.isEmpty)
  #expect(try await vault.library.documentHeader(id: second.id)?.metadata.trashedAt == nil)
  await vault.flush()
}

@Test @MainActor func vaultFiltersAndComposersExplainAndRejectIncompleteActions() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  await vault.waitUntilLoaded()
  vault.suspendBackgroundProcessing()
  let workspace = VaultWorkspaceModel(vault: vault)
  workspace.resume()
  defer { workspace.stop() }
  workspace.tag = "work"
  workspace.dateFilter = .week
  workspace.kindFilter = .listen
  workspace.sourceFilter.appName = "Meeting app"
  workspace.sourceFilter.companionID = "pogo"
  #expect(workspace.activeFilterCount == 5)
  workspace.selectScope(.conversations)
  #expect(workspace.activeFilterCount == 1)
  workspace.clearFilters()
  #expect(workspace.activeFilterCount == 0 && workspace.sourceFilter.isEmpty)
  workspace.selectScope(.all)
  #expect(workspace.activeFilterCount == 0)
  for composer in [VaultNavigation.Composer.collection, .savedSearch] {
    workspace.begin(composer)
    workspace.composeTitle = " \n "
    #expect(!workspace.canSaveComposition)
    await workspace.saveComposedItem()
    #expect(workspace.error == nil && workspace.composer == composer)
    workspace.composeTitle = "Project ideas"
    #expect(workspace.canSaveComposition)
  }
  workspace.begin(.link)
  workspace.composeLink = "   "
  #expect(!workspace.canSaveComposition)
  workspace.composeLink = "https://example.com/ideas"
  #expect(workspace.canSaveComposition)
  await vault.flush()
}

@Test @MainActor func vaultFileOperationsCanBeCancelledAndTheirFeedbackRemainsReadable()
  async throws
{
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  await vault.waitUntilLoaded()
  vault.suspendBackgroundProcessing()
  var completions: [(String?) -> Void] = []
  var cancellations: [@MainActor () -> Void] = []
  let model = SessionVaultModel(
    vault: vault,
    presentation: .init(
      windowActions: .init(
        export: { _, completion in completions.append(completion) }, popOutTranscript: { _ in },
        cancelFileOperation: { cancellations.append($0) })))
  defer { model.stop() }
  model.exportAll()
  await vault.flush()
  #expect(model.canCancelFileOperation)
  model.cancelFileOperation()
  #expect(cancellations.count == 1 && model.isExporting && !model.canExport)
  #expect(!model.canCancelFileOperation)
  model.exportAll()
  await vault.flush()
  #expect(completions.count == 1)
  model.stop()
  model.resume()
  #expect(model.isExporting && !model.canExport)
  #expect(cancellations.count == 1)
  cancellations[0]()
  #expect(!model.isExporting && model.canExport)
  model.exportAll()
  await vault.flush()
  try #require(completions.count == 2)
  completions[0]("An obsolete export failed")
  cancellations[0]()
  #expect(model.feedback == nil && model.isExporting)
  completions[1]("Export stopped. The destination could not be written.")
  try await Task.sleep(for: .seconds(2))
  #expect(model.feedback != nil && model.keepsFeedbackVisible)
  model.dismissFeedback()
  #expect(model.feedback == nil && !model.keepsFeedbackVisible)
}

@Test @MainActor func vaultEveryCategoryAndLongFailuresFitTheCompactWorkspace() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  await vault.waitUntilLoaded()
  vault.suspendBackgroundProcessing()
  let companion = ConversationOwner(id: "pogo", name: "Pogo")
  let failure = SessionFailure(
    category: .recordingSave,
    message: String(repeating: "A long diagnostic to review and copy. ", count: 200))
  let model = SessionVaultModel(
    vault: vault,
    presentation: .init(
      discussion: .init(companions: [companion], open: { _, _ in failure })))
  model.resume()
  defer { model.stop() }
  let conversations = VaultConversationsModel(
    presentation: .init(
      repository: ConversationLibrary(directory: directory.appendingPathComponent("Chat")),
      open: { _, _ in nil }))
  defer { conversations.stop() }
  let root = SessionVaultView(vault: vault, conversations: conversations, model: model)
  for scope in VaultWorkspaceQuery.Scope.allCases {
    model.workspace.selectScope(scope)
    await model.workspace.refresh()
    try await renderSettledSkillInterface(
      root.preferredColorScheme(.light),
      size: SessionVaultWindowController.minimumSize, name: "sillies-vault-audit-\(scope.rawValue)")
  }
  model.workspace.selectScope(.notes)
  await model.workspace.newNote()
  let deadline = ContinuousClock.now + .seconds(3)
  while model.workspace.isOpening, ContinuousClock.now < deadline { await Task.yield() }
  #expect(!model.workspace.isOpening)
  let id = try #require(model.workspace.selectedID)
  model.discuss(id, with: companion)
  await vault.flush()
  #expect(model.discussionFailure == failure)
  let status = NSHostingController(rootView: VaultWorkspaceStatus(vault: vault, model: model))
  #expect(status.sizeThatFits(in: .init(width: 760, height: 560)).height <= 122)
  try await renderSettledSkillInterface(
    root.preferredColorScheme(.light),
    size: SessionVaultWindowController.minimumSize, name: "sillies-vault-audit-long-failure")
  model.dismissDiscussionFailure()
  model.workspace.showsFilters = true
  model.workspace.dateFilter = .range
  model.workspace.sourceFilter.appName = String(repeating: "Long app name ", count: 25)
  try await renderSettledSkillInterface(
    root.preferredColorScheme(.dark),
    size: SessionVaultWindowController.minimumSize, name: "sillies-vault-audit-long-filters")
  await vault.flush()
}

@Test @MainActor func vaultConversationRetryRecoversTheRequestedReadWithoutLosingTheVisiblePage()
  async throws
{
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let store = ConversationLibrary(directory: directory)
  let owner = ConversationOwner(id: "pogo", name: "Pogo")
  let snapshot = try await store.open(owner)
  try await store.save(
    .init(
      handle: snapshot.handle,
      messages: (0..<80).map { ChatMessage(role: .user, text: "Saved thought \($0)") },
      checkpoint: .init(), savedAt: Date()))
  let repository = RecoverableVaultConversationReader(store: store)
  let reader = VaultConversationReaderModel(repository: repository)
  defer { reader.stop() }
  await repository.failNext(.open)
  reader.select(owner)
  await waitForAuditReader(reader)
  #expect(reader.error != nil && reader.page == nil)
  await reader.retry()
  await waitForAuditReader(reader)
  let page = try #require(reader.page)
  #expect(reader.error == nil && page.entries.count == 60)
  let first = try #require(page.entries.first)
  await repository.failNext(.page)
  await reader.move(.before(first.sequence))
  #expect(reader.error != nil && reader.page?.entries.first?.message.id == first.message.id)
  await reader.retry()
  #expect(reader.error == nil && reader.page?.entries.count == 20)
  #expect(await repository.requestedBeforeSequences == [first.sequence, first.sequence])
}

@MainActor private func waitForAuditReader(_ reader: VaultConversationReaderModel) async {
  let deadline = ContinuousClock.now + .seconds(3)
  while reader.isLoading, ContinuousClock.now < deadline { await Task.yield() }
  #expect(!reader.isLoading)
}

private actor RecoverableVaultConversationReader: ConversationRepository {
  enum Operation { case open, page }
  let store: ConversationLibrary
  private var failure: Operation?
  private(set) var requestedBeforeSequences: [Int64] = []
  init(store: ConversationLibrary) { self.store = store }
  func failNext(_ operation: Operation) { failure = operation }
  private func check(_ operation: Operation) throws {
    if failure == operation {
      failure = nil
      throw ConversationStorageError.invalidData
    }
  }
  func open(_ owner: ConversationOwner) async throws -> ConversationSnapshot {
    try check(.open)
    return try await store.open(owner)
  }
  func page(_ request: ConversationPageRequest) async throws -> ConversationPage {
    if case .before(let sequence) = request.position { requestedBeforeSequences.append(sequence) }
    try check(.page)
    return try await store.page(request)
  }
  func save(_ update: ConversationUpdate) async throws { try await store.save(update) }
  func checkpoint(_ handle: ConversationHandle) async throws -> ConversationMemorySnapshot {
    try await store.checkpoint(handle)
  }
  func advanceCheckpoint(_ update: ConversationMemoryUpdate) async throws -> Bool {
    try await store.advanceCheckpoint(update)
  }
  func search(_ request: ConversationSearchRequest) async throws -> [ConversationSearchMatch] {
    try await store.search(request)
  }
  func conversations() async throws -> [ConversationHeader] { try await store.conversations() }
  func clear(_ handle: ConversationHandle) async throws -> ConversationSnapshot {
    try await store.clear(handle)
  }
}
