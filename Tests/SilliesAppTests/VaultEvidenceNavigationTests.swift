import AppKit
import SilliesCore
import SilliesVault
import Testing

@testable import SilliesApp

@Test @MainActor func vaultEvidenceOpensTheExactSectionAndPreservesTheSavedExcerpt() async throws {
  let fixture = try await EvidenceNavigationFixture()
  defer {
    fixture.workspace.stop()
    removeTestFile(at: fixture.directory)
  }
  await fixture.workspace.openEvidence(fixture.passage, action: .read)
  #expect(fixture.workspace.selectedID == fixture.recordID)
  #expect(fixture.workspace.document.section == .notes)
  let request = try #require(fixture.workspace.document.editor.revealRequest)
  #expect(request.presentation == .passage)
  let shown = fixture.workspace.document.editor.text as NSString
  #expect(shown.substring(with: request.range) == fixture.passage.text)
  #expect(!fixture.workspace.document.playback.isPlaying)
  #expect(fixture.workspace.document.editor.selectedText.isEmpty)
  let location = fixture.passage.reference.location
  try await fixture.vault.library.editText(
    .init(
      location: location,
      expectedRevision: fixture.passage.reference.revision, text: "Corrected source"), at: Date())
  await fixture.workspace.openEvidence(fixture.passage, action: .read)
  #expect(fixture.workspace.error != nil)
  #expect(fixture.workspace.document.editor.revealRequest == nil)
  #expect(fixture.passage.text == "Exact source 👩🏽‍💻")
  await fixture.vault.flush()
}

@Test @MainActor func vaultEvidenceDoesNotPublishAfterNavigationOrCloseSupersedesItsRequest()
  async throws
{
  let fixture = try await EvidenceNavigationFixture()
  defer {
    fixture.workspace.stop()
    removeTestFile(at: fixture.directory)
  }
  let task = Task { await fixture.workspace.openEvidence(fixture.passage, action: .read) }
  await Task.yield()
  fixture.workspace.selectScope(.trash)
  await task.value
  #expect(fixture.workspace.selectedID == nil)
  #expect(fixture.workspace.sidebarSelection == .scope(.trash))
  let next = Task { await fixture.workspace.openEvidence(fixture.passage, action: .read) }
  fixture.workspace.stop()
  await next.value
  #expect(!fixture.workspace.isPresented)
  #expect(fixture.workspace.document.editor.revealRequest == nil)
  await fixture.vault.flush()
}

@Test @MainActor func vaultEvidenceDestinationUsesOneNativeWindowAndCancelsSupersededOpens()
  async throws
{
  let fixture = try await EvidenceNavigationFixture()
  let owner = SessionVaultWindowController(
    vault: fixture.vault, appearance: ThemeEnvironment(), services: .init())
  defer {
    owner.close()
    fixture.workspace.stop()
    removeTestFile(at: fixture.directory)
  }
  owner.prepare(.evidence(fixture.passage, .read))
  let window = try #require(owner.window)
  let root = try #require(window.contentView)
  let deadline = ContinuousClock.now.advanced(by: .seconds(3))
  while owner.model.workspace.document.editor.revealRequest == nil, ContinuousClock.now < deadline {
    try await Task.sleep(for: .milliseconds(5))
  }
  #expect(owner.model.workspace.document.editor.revealRequest?.presentation == .passage)
  #expect(!owner.model.workspace.document.playback.isPlaying)
  owner.prepare(.evidence(fixture.passage, .read))
  owner.prepare(.record(fixture.recordID))
  #expect(owner.window === window && window.contentView === root)
  #expect(window.attachedSheet == nil)
  owner.close()
  await Task.yield()
  #expect(!owner.model.workspace.isPresented)
  await fixture.vault.flush()
}

private struct EvidenceNavigationFixture {
  let directory: URL
  let vault: SessionVaultStore
  let workspace: VaultWorkspaceModel
  let passage: VaultEvidencePassage
  let recordID: UUID

  @MainActor init() async throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    vault = SessionVaultStore(directory: directory)
    await vault.waitUntilLoaded()
    vault.suspendBackgroundProcessing()
    let header = try await vault.createDocument(
      metadata: .init(kind: .note, title: "Evidence", modifiedAt: Date()),
      notes: "A prefix. Exact source 👩🏽‍💻. A suffix.")
    recordID = header.id
    let block = try #require(
      try await vault.library.sectionPage(.init(recordID: header.id, section: .notes)).blocks.first)
    passage = try #require(
      VaultEvidencePassage(
        block: block, scalarOffset: "A prefix. ".unicodeScalars.count, text: "Exact source 👩🏽‍💻"))
    workspace = VaultWorkspaceModel(vault: vault)
    workspace.resume()
  }
}
