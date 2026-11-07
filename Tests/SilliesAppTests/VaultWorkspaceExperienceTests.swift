import AVFoundation
import AppKit
import SilliesCore
import SilliesPersistence
import SilliesVault
import SwiftUI
import Testing

@testable import SilliesApp

@Test @MainActor func vaultNativeEditorPreservesCompositionAndUndoAcrossAutosave() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  await vault.waitUntilLoaded()
  vault.suspendBackgroundProcessing()
  let header = try await vault.createDocument(
    metadata: .init(kind: .note, title: "Words", modifiedAt: Date()), notes: "Salut ")
  let model = VaultTextEditorModel(vault: vault)
  await model.load(.init(recordID: header.id, section: .notes))
  let coordinator = VaultNativeTextEditor.Coordinator(model: model)
  let text = NSTextView(usingTextLayoutManager: true)
  text.isRichText = false
  text.allowsUndo = true
  text.delegate = coordinator
  text.string = model.text
  let window = NSWindow(
    contentRect: .init(x: 0, y: 0, width: 500, height: 300), styleMask: [.titled],
    backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  window.contentView = text
  defer { window.close() }
  #expect(window.makeFirstResponder(text))
  let undo = try #require(text.undoManager)
  undo.groupsByEvent = false
  undo.beginUndoGrouping()
  text.setMarkedText(
    "你", selectedRange: .init(location: 1, length: 0),
    replacementRange: .init(location: 6, length: 0))
  #expect(text.hasMarkedText())
  #expect(model.text == "Salut ")
  text.insertText(
    "你好 — Bună ziua مرحبا 🌳", replacementRange: .init(location: NSNotFound, length: 0))
  undo.endUndoGrouping()
  #expect(!text.hasMarkedText())
  let completed = text.string
  #expect(model.text == completed && completed.contains("你好"))
  await model.flush()
  #expect(!model.isDirty && model.error == nil)
  #expect(text.tryToPerform(NSSelectorFromString("undo:"), with: nil))
  try await Task.sleep(for: .milliseconds(20))
  #expect(!text.hasMarkedText())
  #expect(text.delegate != nil)
  #expect(text.string == "Salut " && model.text == "Salut ")
  #expect(text.tryToPerform(NSSelectorFromString("redo:"), with: nil))
  try await Task.sleep(for: .milliseconds(20))
  #expect(text.string == completed && model.text == completed)
  await model.flush()
  let saved = try await vault.library.sectionPage(.init(recordID: header.id, section: .notes))
  #expect(saved.blocks.map(\.text).joined() == completed)
  #expect(!window.isVisible)
  model.stop()
  await vault.flush()
  withExtendedLifetime(coordinator) {}
}

@Test @MainActor func vaultQuotingAnEditedPageWaitsForCurrentSourceReferences() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  await vault.waitUntilLoaded()
  vault.suspendBackgroundProcessing()
  let header = try await vault.createDocument(
    metadata: .init(kind: .note, title: "Source", modifiedAt: Date()), notes: "Original")
  let workspace = VaultWorkspaceModel(vault: vault)
  workspace.resume()
  workspace.select(header.id)
  try await waitForWorkspaceDocument(workspace, id: header.id)
  let editor = workspace.document.editor
  let original = try #require(editor.blocks.first)
  let replacement =
    String(repeating: "A revised paragraph.\n", count: 2_000) + "The selected conclusion."
  editor.replaceText(replacement)
  editor.selectText((replacement as NSString).range(of: "The selected conclusion."))
  await workspace.quoteSelection()
  let quotation = try #require(workspace.quotation)
  #expect(quotation.text == "The selected conclusion.")
  #expect(quotation.reference.blockID != original.id)
  let source = try await vault.library.sourceLocation(quotation.reference)
  #expect(source != nil)
  #expect(editor.blocks.count > VaultSectionPage.maximumBlocks)
  #expect(editor.blocks.map(\.text).joined() == replacement)
  #expect(!editor.isDirty && editor.error == nil)
  workspace.stop()
  await vault.flush()
}

@Test @MainActor func vaultConversationFilteringAndSwitchingPreserveCompanionIdentity() async throws
{
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let repository = ConversationLibrary(directory: directory)
  let pogo = ConversationOwner(id: "pogo", name: "Pogo")
  let bolt = ConversationOwner(id: "bolt", name: "Bolt")
  for (owner, count) in [(bolt, 3), (pogo, 80)] {
    let snapshot = try await repository.open(owner)
    try await repository.save(
      .init(
        handle: snapshot.handle,
        messages: (0..<count).map {
          ChatMessage(role: .user, text: "Project quartz \(owner.name) \($0)")
        },
        checkpoint: .init(), savedAt: Date()))
  }
  let model = VaultConversationsModel(
    presentation: .init(repository: repository, open: { _, _ in nil }))
  model.query = "quartz"
  model.companionID = bolt.id
  await model.load()
  #expect(model.results.count == 3)
  #expect(model.results.allSatisfy { $0.owner == bolt })
  model.query = ""
  await model.load()
  #expect(model.headers.map(\.owner) == [bolt])
  #expect(try await model.companionChoices(matching: "Pog").map(\.id) == [pogo.id])

  model.reader.select(pogo)
  let deadline = ContinuousClock.now.advanced(by: .seconds(2))
  while model.reader.isLoading, ContinuousClock.now < deadline {
    try await Task.sleep(for: .milliseconds(5))
  }
  #expect(model.reader.page?.entries.isEmpty == false)
  model.reader.select(bolt)
  #expect(model.reader.owner == bolt)
  #expect(model.reader.page == nil)
  #expect(model.reader.error == nil)
  model.stop()
  await model.load()
  let resumedDeadline = ContinuousClock.now + .seconds(2)
  while model.reader.isLoading, ContinuousClock.now < resumedDeadline { await Task.yield() }
  #expect(
    model.reader.owner == bolt && model.reader.page?.entries.count == 3,
    "Returning after a cancelled initial load must resume the selected conversation.")
  model.reader.clear()
  model.query = ""
  model.companionID = nil
  let vault = SessionVaultStore(directory: directory.appendingPathComponent("Captures"))
  await vault.waitUntilLoaded()
  let workspace = SessionVaultModel(vault: vault, presentation: .init())
  workspace.resume()
  workspace.workspace.selectScope(.conversations)
  let root = SessionVaultView(vault: vault, conversations: model, model: workspace)
  try await renderSettledSkillInterface(
    root.preferredColorScheme(.light), size: SessionVaultWindowController.minimumSize,
    name: "sillies-vault-conversations-compact")
  model.reader.select(bolt)
  try await renderSettledSkillInterface(
    root.preferredColorScheme(.light), size: SessionVaultWindowController.initialSize,
    name: "sillies-vault-conversation-wide")
  workspace.stop()
  model.stop()
  await vault.flush()
}

@Test @MainActor func vaultSourceLinksReuseTheWorkspaceAndExplainRemovedSources() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  await vault.waitUntilLoaded()
  vault.suspendBackgroundProcessing()
  let header = try await vault.createDocument(
    metadata: .init(kind: .note, title: "Linked source", modifiedAt: Date()),
    notes: "The original quoted passage.")
  let block = try #require(
    try await vault.library.sectionPage(.init(recordID: header.id, section: .notes)).blocks.first)
  let reference = VaultSourceReference(block: block)
  let owner = SessionVaultWindowController(
    vault: vault, appearance: ThemeEnvironment(), services: .init())
  defer { owner.close() }
  owner.prepare(.source(reference))
  let window = try #require(owner.window)
  let deadline = ContinuousClock.now.advanced(by: .seconds(2))
  while owner.model.workspace.document.header?.id != header.id, ContinuousClock.now < deadline {
    try await Task.sleep(for: .milliseconds(5))
  }
  #expect(owner.model.workspace.document.header?.id == header.id)
  owner.prepare(.source(reference))
  #expect(owner.window === window)
  vault.remove(id: header.id)
  await vault.flush()
  await owner.model.workspace.openSource(reference)
  #expect(owner.model.workspace.error?.isEmpty == false)
}

@Test @MainActor
func vaultWorkspaceReadingInteractionPausesAudioFollowingAndNavigationRemembersPassages()
  async throws
{
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  await vault.waitUntilLoaded()
  vault.suspendBackgroundProcessing()
  let header = try await vault.createDocument(
    metadata: .init(kind: .note, title: "Long note", modifiedAt: Date()),
    notes: String(repeating: "A remembered passage.\n", count: 6_000))
  let workspace = VaultWorkspaceModel(vault: vault)
  workspace.resume()
  workspace.select(header.id)
  try await waitForWorkspaceDocument(workspace, id: header.id)
  let middle = VaultBlockLocation(recordID: header.id, section: .notes, ordinal: 20)
  workspace.visit(middle)
  try await waitForWorkspaceDocument(workspace, id: header.id)
  #expect(workspace.document.editor.location == middle)
  workspace.goBack()
  try await waitForWorkspaceDocument(workspace, id: header.id)
  #expect(workspace.document.editor.location?.ordinal == 0)
  workspace.goForward()
  try await waitForWorkspaceDocument(workspace, id: header.id)
  #expect(workspace.document.editor.location == middle)
  workspace.document.recording.resumeFollowing()
  workspace.document.editor.selectText(NSRange(location: 0, length: 4))
  #expect(!workspace.document.recording.isFollowing)
  workspace.document.recording.resumeFollowing()
  workspace.document.editor.replaceText("Corrected words")
  #expect(!workspace.document.recording.isFollowing)
  await workspace.document.flush()
  workspace.stop()
}

@Test @MainActor func vaultWorkspaceFitsCompactAndWideWindowsWithAnEditableDocument() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  await vault.waitUntilLoaded()
  vault.suspendBackgroundProcessing()
  let header = try await vault.createDocument(
    metadata: .init(kind: .note, title: "A calmer way to plan the week", modifiedAt: Date()),
    notes:
      "Keep the good ideas together.\n\nNext week, leave a little room for discovery. Start with the things that matter, then make space for the unexpected.\n\n- A shared place for meeting decisions\n- A few links worth coming back to\n- One small thing to try tomorrow"
  )
  let model = SessionVaultModel(vault: vault, presentation: .init())
  model.resume()
  await model.workspace.refresh()
  model.workspace.select(header.id)
  try await waitForWorkspaceDocument(model.workspace, id: header.id)
  let root = SessionVaultView(
    vault: vault, conversations: nil, model: model)
  try await renderSettledSkillInterface(
    root.preferredColorScheme(.light), size: SessionVaultWindowController.initialSize,
    name: "sillies-vault-workspace-light")
  try await renderSettledSkillInterface(
    root.preferredColorScheme(.dark), size: SessionVaultWindowController.initialSize,
    name: "sillies-vault-workspace-dark")
  try await renderSettledSkillInterface(
    root.preferredColorScheme(.light), size: SessionVaultWindowController.minimumSize,
    name: "sillies-vault-workspace-compact")
  model.workspace.document.editor.selectText(NSRange(location: 0, length: 29))
  await model.workspace.quoteSelection()
  #expect(model.workspace.quotation != nil)
  try await renderSettledSkillInterface(
    root.preferredColorScheme(.light), size: SessionVaultWindowController.minimumSize,
    name: "sillies-vault-quote-compact")
  model.workspace.showLibrary()
  model.workspace.showsFilters = true
  model.workspace.dateFilter = .range
  try await renderSettledSkillInterface(
    root.preferredColorScheme(.light), size: SessionVaultWindowController.minimumSize,
    name: "sillies-vault-filters-compact")
  model.workspace.showsFilters = false
  model.workspace.dateFilter = .any
  model.workspace.begin(.link)
  try await renderSettledSkillInterface(
    root.preferredColorScheme(.light), size: SessionVaultWindowController.minimumSize,
    name: "sillies-vault-link-compact")
  model.workspace.showLibrary()
  model.workspace.showStorage()
  try await renderSettledSkillInterface(
    root.preferredColorScheme(.light), size: SessionVaultWindowController.minimumSize,
    name: "sillies-vault-storage-compact")
  model.stop()
  await vault.flush()
}

@Test @MainActor func vaultRecordingAndFileActionsFitTheCompactReader() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  await vault.waitUntilLoaded()
  vault.suspendBackgroundProcessing()
  var meeting = SessionRecord(
    kind: .listen,
    origin: .init(
      characterID: "pogo", characterName: "Pogo", source: .init(appName: "Project review")),
    content: .init(
      text: .init(
        transcript:
          "[00:00] Alex: Let's make the next version easier to use.\n[00:12] You: Keep notes and recordings together, with room for our own ideas."
      )),
    metadata: .init(durationSeconds: 20))
  meeting.audioFilename = "layout-fixture.wav"
  let audio = try #require(vault.audioURL(for: meeting))
  try await Task.detached {
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 320_000))
    buffer.frameLength = buffer.frameCapacity
    let samples = try #require(buffer.floatChannelData?.pointee)
    samples.update(repeating: 0, count: Int(buffer.frameLength))
    let file = try AVAudioFile(forWriting: audio, settings: format.settings)
    try file.write(from: buffer)
  }.value
  vault.add(meeting)
  await vault.flush()
  let model = SessionVaultModel(vault: vault, presentation: .init())
  model.resume()
  await model.workspace.refresh()
  model.workspace.select(meeting.id)
  try await waitForWorkspaceDocument(model.workspace, id: meeting.id)
  await model.workspace.document.recording.open(meeting.id)
  await model.workspace.document.recording.addBookmark(seconds: 12, recordID: meeting.id)
  #expect(model.workspace.document.recording.bookmarks.count == 1)
  #expect(model.workspace.document.playback.error == nil)
  #expect(abs(model.workspace.document.playback.duration - 20) < 0.1)
  model.workspace.document.playback.seek(to: 12)
  let root = SessionVaultView(
    vault: vault, conversations: nil, model: model)
  try await renderSettledSkillInterface(
    root.preferredColorScheme(.light), size: SessionVaultWindowController.minimumSize,
    name: "sillies-vault-recording-compact")
  let file = SessionRecord(
    kind: .stash,
    origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Stash")),
    content: .init(text: .init(stashedItems: ["/Users/Shared/Project notes.md"])))
  vault.add(file)
  await vault.flush()
  await model.workspace.refresh()
  model.workspace.select(file.id)
  try await waitForWorkspaceDocument(model.workspace, id: file.id)
  await model.workspace.document.externalFiles.load(id: file.id)
  await model.workspace.document.selectPane(.files)
  #expect(model.workspace.document.externalFiles.references.count == 1)
  await model.workspace.document.open(file.id, match: .init(recordID: file.id, section: .files))
  #expect(model.workspace.document.pane == .files)
  #expect(model.workspace.document.panes.contains(model.workspace.document.pane))
  try await renderSettledSkillInterface(
    root.preferredColorScheme(.light), size: SessionVaultWindowController.minimumSize,
    name: "sillies-vault-files-compact")
  model.stop()
  await vault.flush()
}

@Test @MainActor func vaultWorkspaceSavesNotesAcrossNavigationAndRestartWithoutLoadingBodies()
  async throws
{
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  await vault.waitUntilLoaded()
  vault.suspendBackgroundProcessing()
  let first = try await vault.createDocument(
    metadata: .init(kind: .note, title: "First", modifiedAt: Date()))
  let second = try await vault.createDocument(
    metadata: .init(kind: .note, title: "Second", modifiedAt: Date()))
  let model = VaultDocumentModel(vault: vault)
  await model.open(first.id)
  model.editor.replaceText("A durable thought with diacritics: încredere. 👩🏽‍💻")
  await model.open(second.id)
  #expect(model.header?.id == second.id)
  #expect(model.editor.text.isEmpty)
  await vault.flush()
  #expect(try await vault.library.metrics().loadedBodies == 0)
  let reopened = VaultLibrary(directory: directory)
  let page = try await reopened.sectionPage(.init(recordID: first.id, section: .notes))
  #expect(page.blocks.map(\.text).joined().contains("încredere"))
  #expect(try await reopened.draft(.init(recordID: first.id, section: .notes)) == nil)
  model.stop()
}

@Test @MainActor func vaultWorkspaceDraftFlushCompletesInTheTerminationModalRunLoop() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  await vault.waitUntilLoaded()
  vault.suspendBackgroundProcessing()
  let header = try await vault.createDocument(
    metadata: .init(kind: .note, title: "Before quitting", modifiedAt: Date()))
  let editor = VaultTextEditorModel(vault: vault)
  await editor.load(.init(recordID: header.id, section: .notes))
  editor.replaceText("Keep the final keystroke.")
  var completed = false
  vault.flushOnIOQueue { MainActor.assumeIsolated { completed = true } }
  pumpWorkspaceTermination { completed }
  #expect(completed)
  #expect(!editor.isDirty && editor.error == nil)
  let reopened = VaultLibrary(directory: directory)
  #expect(
    try await reopened.sectionPage(.init(recordID: header.id, section: .notes)).blocks.first?.text
      == "Keep the final keystroke.")
  editor.stop()
}

@MainActor private func pumpWorkspaceTermination(_ complete: () -> Bool) {
  let deadline = ContinuousClock.now.advanced(by: .seconds(3))
  let mode = CFRunLoopMode(RunLoop.Mode.modalPanel.rawValue as CFString)
  while !complete(), ContinuousClock.now < deadline { CFRunLoopRunInMode(mode, 0.01, true) }
}

@Test @MainActor func vaultWorkspaceConflictPreservesDraftWithoutOverwritingAnotherEdit()
  async throws
{
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  await vault.waitUntilLoaded()
  vault.suspendBackgroundProcessing()
  let header = try await vault.createDocument(
    metadata: .init(kind: .note, title: "Conflict", modifiedAt: Date()), notes: "Original")
  let location = VaultBlockLocation(recordID: header.id, section: .notes)
  let first = VaultTextEditorModel(vault: vault)
  let second = VaultTextEditorModel(vault: vault)
  await first.load(location)
  await second.load(location)
  first.replaceText("First author's change")
  await first.flush()
  second.replaceText("Second author's draft")
  await second.flush()
  #expect(second.error != nil && second.recoverySaved)
  #expect(
    try await vault.library.sectionPage(location).blocks.first?.text == "First author's change")
  #expect(try await vault.library.draft(location)?.text == "Second author's draft")
  first.stop()
  second.stop()
}

@Test @MainActor func vaultWorkspaceFlushesTitleAndTagsWithoutLosingFocus() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  await vault.waitUntilLoaded()
  vault.suspendBackgroundProcessing()
  let first = try await vault.createDocument(
    metadata: .init(kind: .note, title: "First", modifiedAt: Date()))
  let second = try await vault.createDocument(
    metadata: .init(kind: .note, title: "Second", modifiedAt: Date()))
  let document = VaultDocumentModel(vault: vault)
  await document.open(first.id)
  document.title = "  Renamed before navigation  "
  document.tags = "work, personal, work"
  await document.open(second.id)
  let saved = try #require(try await vault.library.documentHeader(id: first.id))
  #expect(saved.title == "Renamed before navigation")
  #expect(saved.metadata.tags == ["personal", "work"])
  #expect(try await vault.library.metadataDraft(id: first.id) == nil)
  document.title = "Final keystroke"
  var complete = false
  vault.flushOnIOQueue { MainActor.assumeIsolated { complete = true } }
  pumpWorkspaceTermination { complete }
  #expect(complete)
  #expect(try await vault.library.documentHeader(id: second.id)?.title == "Final keystroke")
  document.stop()
}

@Test @MainActor func vaultWorkspaceRecoversConflictingDraftAsAnIndependentNote() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  await vault.waitUntilLoaded()
  vault.suspendBackgroundProcessing()
  let original = try await vault.createDocument(
    metadata: .init(kind: .note, title: "Shared", modifiedAt: Date()), notes: "Initial")
  let editor = VaultTextEditorModel(vault: vault)
  let location = VaultBlockLocation(recordID: original.id, section: .notes)
  await editor.load(location)
  editor.replaceText("My unsaved version")
  _ = try await vault.library.editText(
    .init(location: location, expectedRevision: editor.revision, text: "Another version"),
    at: Date())
  await editor.flush()
  #expect(editor.recoveredDraft)
  let recovered = try #require(try await editor.recoverAsNote())
  #expect(recovered != original.id)
  #expect(
    try await vault.library.sectionPage(location).blocks.map(\.text).joined() == "Another version")
  #expect(
    try await vault.library.sectionPage(.init(recordID: recovered, section: .notes)).blocks.map(
      \.text
    ).joined() == "My unsaved version")
  #expect(try await vault.library.draft(location) == nil)
  editor.stop()
}

@Test @MainActor func vaultWorkspaceReopenKeepsItsLongDocumentPageAndExplicitLinksLeaveOtherPanes()
  async throws
{
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  await vault.waitUntilLoaded()
  vault.suspendBackgroundProcessing()
  let header = try await vault.createDocument(
    metadata: .init(kind: .note, title: "Long note", modifiedAt: Date()),
    notes: String(repeating: "A remembered paragraph. ", count: 4_000))
  let owner = SessionVaultWindowController(
    vault: vault, appearance: ThemeEnvironment(), services: .init())
  owner.prepare(.record(header.id))
  try await waitForWorkspaceDocument(owner.model.workspace, id: header.id)
  await owner.model.workspace.document.editor.move(to: 16)
  #expect(owner.model.workspace.document.editor.location?.ordinal == 16)
  owner.hide()
  owner.prepare()
  try await waitForWorkspaceDocument(owner.model.workspace, id: header.id)
  #expect(owner.model.workspace.document.editor.location?.ordinal == 16)
  owner.model.workspace.selectScope(.conversations)
  owner.model.workspace.begin(.link)
  owner.model.workspace.showStorage()
  owner.prepare(.record(header.id))
  #expect(owner.model.workspace.scope == .all)
  #expect(
    owner.model.workspace.composer == nil && owner.model.workspace.navigation.page == .library)
  owner.close()
  await vault.flush()
}

@MainActor private func waitForWorkspaceDocument(_ workspace: VaultWorkspaceModel, id: UUID)
  async throws
{
  let deadline = ContinuousClock.now.advanced(by: .seconds(3))
  while workspace.document.header?.id != id || workspace.isOpening || workspace.document.isLoading {
    guard ContinuousClock.now < deadline else { throw CocoaError(.executableRuntimeMismatch) }
    await Task.yield()
  }
}

@Test @MainActor func vaultWorkspaceFailedFirstOpenKeepsItsDestinationAndCanRetry() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let databaseURL = directory.appendingPathComponent(VaultDatabase.filename)
  try Data("Unreadable fixture".utf8).write(to: databaseURL)
  let record = SessionRecord(
    kind: .stash,
    origin: .init(characterID: "vault", characterName: "", source: .init(appName: "Fixture")))
  let vault = SessionVaultStore(directory: directory)
  await vault.waitUntilLoaded()
  let model = SessionVaultModel(vault: vault, presentation: .init())
  model.resume()
  model.workspace.select(record.id)
  let deadline = ContinuousClock.now.advanced(by: .seconds(3))
  while model.workspace.isOpening, ContinuousClock.now < deadline { await Task.yield() }
  #expect(!model.workspace.isOpening)
  #expect(model.workspace.document.header == nil && model.workspace.document.error != nil)
  #expect(model.workspace.selectedID == record.id)
  try await renderSettledSkillInterface(
    SessionVaultView(vault: vault, conversations: nil, model: model)
      .preferredColorScheme(.light),
    size: SessionVaultWindowController.minimumSize, name: "sillies-vault-unavailable-compact")

  try FileManager.default.removeItem(at: databaseURL)
  let restored = VaultLibrary(directory: directory)
  _ = try await restored.createDocument(
    record: record, metadata: .init(kind: .note, title: "Restored", modifiedAt: Date()),
    notes: "Recovered after an unavailable archive")
  vault.retrySaving()
  await vault.waitUntilLoaded()
  model.workspace.retrySelection()
  try await waitForWorkspaceDocument(model.workspace, id: record.id)
  #expect(model.workspace.document.error == nil)
  #expect(model.workspace.document.editor.text == "Recovered after an unavailable archive")
  model.stop()
  await vault.flush()
}
