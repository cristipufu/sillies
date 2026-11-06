import AppKit
import SilliesChat
import SilliesCore
import SilliesPersistence
import SilliesReasoning
import SilliesVault
import Testing

@testable import SilliesApp

@Test @MainActor func companionSwitchDeliversNavigationAfterTheRequestedSessionOpens() async throws
{
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let coordinator = SkillCoordinator(vault: SessionVaultStore(directory: directory))
  coordinator.makeChatSession = { id, name in
    ChatWindowFixture.makeReadySession(
      conversation: NavigationReply(), history: .transient,
      owner: .init(id: id, name: name))
  }
  var opened: [String] = []
  coordinator.onOpenChatSession = { opened.append($0.companionID) }
  #expect(coordinator.startConversation(.chat, for: "pogo", name: "Pogo") == nil)
  var navigated: String?
  let failure = coordinator.openConversation(for: .init(id: "bolt", name: "Bolt")) { session in
    #expect(opened.last == "bolt")
    #expect(coordinator.activeChatSession === session)
    navigated = session.companionID
  }
  #expect(failure == nil)
  for _ in 0..<200 {
    if navigated != nil { break }
    try await Task.sleep(for: .milliseconds(5))
  }
  #expect(navigated == "bolt" && opened == ["pogo", "bolt"])
  await coordinator.shutdown()
}

private struct NavigationReply: ConversationResponding {
  func reply(to context: ChatContext, progress: @escaping @Sendable (ChatProgress) -> Void)
    async throws -> ChatReply
  {
    .init(text: "Hello")
  }
}

@Test @MainActor func vaultConversationLinksSurfaceFailureAndIgnoreCancelledCompletions() async {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let library = ConversationLibrary(directory: directory)
  let failure = SessionFailure(
    category: .captureUnavailable, message: "A recording is already running.")
  var calls = 0
  var resume: CheckedContinuation<SessionFailure?, Never>?
  let model = VaultConversationsModel(
    presentation: .init(
      repository: library,
      open: { _, _ in
        calls += 1
        if calls == 1 { return failure }
        return await withCheckedContinuation { resume = $0 }
      }))
  model.open(.init(id: "pogo", name: "Pogo"))
  for _ in 0..<1_000 {
    if !model.isOpening { break }
    await Task.yield()
  }
  #expect(model.openFailure == failure && !model.isOpening)
  model.open(.init(id: "pogo", name: "Pogo"))
  for _ in 0..<1_000 {
    if resume != nil { break }
    await Task.yield()
  }
  #expect(resume != nil)
  model.open(.init(id: "pogo", name: "Pogo"))
  #expect(calls == 2)
  model.stop()
  resume?.resume(returning: failure)
  for _ in 0..<20 { await Task.yield() }
  #expect(!model.isOpening && model.openFailure == nil)
}

@Test @MainActor func vaultReopeningRetainsItsRootAndExplicitOlderRecordSelection() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  await vault.waitUntilLoaded()
  let recordCount = VaultPageRequest.maximumPageSize + 25
  let records = (0..<recordCount).map { index in
    SessionRecord(
      kind: .record,
      origin: .init(
        characterID: "pogo", characterName: "Pogo", source: .init(appName: "Meeting \(index)")),
      content: .init(text: .init(transcript: "Transcript \(index)")),
      metadata: .init(createdAt: Date(timeIntervalSince1970: Double(index))))
  }
  for record in records { vault.add(record) }
  await vault.flush()
  let owner = SessionVaultWindowController(
    vault: vault, appearance: ThemeEnvironment(), services: .init())
  defer { owner.close() }
  owner.model.navigate(to: records[0].id)
  await owner.model.refreshSearch()
  await owner.model.loadSelection()
  #expect(owner.model.selectedRecordID == records[0].id)
  #expect(owner.model.visibleDetail?.transcript == records[0].transcript)
  #expect(owner.model.selectedHeader(in: owner.model.filteredRecords) == nil)
  let newest = try #require(records.last)
  owner.model.searchQuery = newest.appName
  await owner.model.refreshSearch()
  #expect(owner.model.selectedRecordID == newest.id)
  owner.model.navigate(to: records[0].id)
  await owner.model.refreshSearch()
  await owner.model.loadSelection()
  owner.prepare()
  let window = try #require(owner.window)
  let root = try #require(window.contentViewController)
  owner.model.openTranscript(records[0])
  owner.hide()
  owner.prepare()
  #expect(owner.window === window && owner.window?.contentViewController === root)
  #expect(owner.model.expandedTranscriptID == records[0].id)
  #expect(owner.model.visibleDetail?.id == records[0].id)
  owner.model.searchQuery = newest.appName
  owner.hide()
  owner.prepare()
  #expect(owner.model.searchQuery == newest.appName)
  owner.prepare(.record(newest.id))
  #expect(owner.model.selectedRecordID == newest.id && owner.model.searchQuery.isEmpty)
  #expect(owner.window?.contentViewController === root)
  owner.prepare(.stash)
  #expect(owner.model.selectedFilter == .stash && owner.model.searchQuery.isEmpty)
}

@Test @MainActor func missingVaultLinkDoesNotOpenAnUnrelatedRecord() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  await vault.waitUntilLoaded()
  let requested = UUID()
  let model = SessionVaultModel(vault: vault, presentation: .init(initialRecordID: requested))
  await model.refreshSearch()
  await model.loadSelection()
  #expect(model.selectedRecordID == requested)
  #expect(model.visibleDetail == nil && model.detailError != nil)
  model.stop()
}

@Test @MainActor func savedTranscriptReusesItsWindowAndNativeViewportUntilRecordChanges() throws {
  let owner = SavedTranscriptWindow(appearance: ThemeEnvironment())
  defer { owner.close() }
  let id = UUID()
  owner.prepare("One\nTwo\nThree", title: "Transcript", id: id)
  let window = try #require(owner.window)
  let root = try #require(window.contentViewController)
  owner.prepare("One\nTwo\nThree", title: "Renamed", id: id)
  #expect(owner.window === window && window.contentViewController === root)
  #expect(window.title == "Renamed")
  owner.prepare("Another transcript", title: "Another", id: UUID())
  #expect(owner.window === window && window.contentViewController !== root)
}

@Test @MainActor func stashPickerOwnsSearchLifetimeAcrossCloseAndReopen() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  vault.suspendBackgroundProcessing()
  await vault.waitUntilLoaded()
  let record = SessionRecord(
    kind: .stash,
    origin: .init(characterID: "pogo", characterName: "Pogo", source: .init(appName: "Stash")),
    content: .init(text: .init(stashedItems: ["A saved note"])))
  vault.add(record)
  await vault.flush()
  vault.pin(record)
  let owner = StashPickerController(vault: vault, appearance: ThemeEnvironment())
  #expect(!owner.model.isPresented)
  #expect(vault.pinnedRecordID == record.id)
  owner.prepare()
  let window = try #require(owner.window)
  let root = try #require(window.contentViewController)
  defer {
    owner.stop()
    window.close()
  }
  try await waitForStashResults(owner, ids: [record.id])
  window.close()
  #expect(!owner.model.isPresented)
  #expect(vault.pinnedRecordID == record.id)
  owner.model.searchQuery = "not present"
  owner.prepare()
  try await waitForStashResults(owner, ids: [])
  #expect(owner.window === window && window.contentViewController === root)
  #expect(owner.model.isPresented)
  owner.stop()
  #expect(!owner.model.isPresented)
  owner.model.searchQuery = "saved"
  owner.prepare()
  try await waitForStashResults(owner, ids: [record.id])
}

@MainActor private func waitForStashResults(_ owner: StashPickerController, ids: [UUID])
  async throws
{
  let deadline = ContinuousClock.now.advanced(by: .seconds(2))
  repeat {
    owner.window?.contentView?.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(5))
    if !owner.model.isSearching, owner.model.keywordRecords.map(\.id) == ids { return }
  } while ContinuousClock.now < deadline
  #expect(owner.model.keywordRecords.map(\.id) == ids)
  #expect(!owner.model.isSearching)
}
