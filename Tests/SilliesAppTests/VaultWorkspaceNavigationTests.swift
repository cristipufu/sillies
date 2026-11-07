import AppKit
import SilliesCore
import SwiftUI
import Testing

@testable import SilliesApp

@Test @MainActor func vaultSidebarDestinationsReplaceFormsAndStorageIncludingTheCurrentScope()
  async throws
{
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  await vault.waitUntilLoaded()
  vault.suspendBackgroundProcessing()
  let workspace = VaultWorkspaceModel(vault: vault)
  workspace.resume()
  defer { workspace.stop() }
  let initialTransition = workspace.navigation.transitionID
  workspace.selectScope(.all)
  #expect(!workspace.canGoBack)
  #expect(workspace.navigation.transitionID != initialTransition)
  for scope in VaultWorkspaceQuery.Scope.allCases {
    workspace.selectScope(scope)
    workspace.showStorage()
    #expect(workspace.sidebarSelection == .storage)
    workspace.selectScope(scope)
    #expect(workspace.navigation.page == .library)
    #expect(workspace.sidebarSelection == .scope(scope))
    workspace.begin(.link)
    #expect(workspace.sidebarSelection == nil)
    workspace.selectScope(scope)
    #expect(workspace.composer == nil && workspace.quotation == nil)
    #expect(workspace.sidebarSelection == .scope(scope))
  }
  let collection = VaultCollection(name: "Weekend ideas")
  try await vault.library.saveCollection(collection)
  workspace.showStorage()
  workspace.selectCollection(collection.id)
  #expect(workspace.sidebarSelection == .collection(collection.id))
  workspace.begin(.collection)
  workspace.composeTitle = "Another collection"
  workspace.showStorage()
  #expect(workspace.composer == nil)
  workspace.goBack()
  #expect(workspace.composer == .collection && workspace.composeTitle == "Another collection")
  workspace.begin(.link)
  workspace.composeTitle = "A different draft"
  workspace.goBack()
  #expect(workspace.composer == .collection && workspace.composeTitle == "Another collection")
  workspace.apply(.init(name: "Notes", query: .init(scope: .notes, text: "weekend")))
  #expect(workspace.navigation.page == .library)
  #expect(workspace.collectionID == nil && workspace.searchText == "weekend")
  #expect(workspace.sidebarSelection == .scope(.notes))
  await vault.flush()
}

@Test @MainActor func vaultLateDocumentLoadsDoNotRestoreSelectionAfterLeavingTheirSection()
  async throws
{
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  await vault.waitUntilLoaded()
  vault.suspendBackgroundProcessing()
  let header = try await vault.createDocument(
    metadata: .init(kind: .note, title: "Previous section", modifiedAt: Date()),
    notes: "Saved content")
  let workspace = VaultWorkspaceModel(vault: vault)
  workspace.resume()
  defer { workspace.stop() }
  for _ in 0..<8 {
    workspace.selectScope(.notes)
    workspace.select(header.id)
    workspace.selectScope(.trash)
    await Task.yield()
    #expect(workspace.selectedID == nil && workspace.selectedIDs.isEmpty)
    #expect(workspace.sidebarSelection == .scope(.trash))
  }
  workspace.showStorage()
  await workspace.newNote()
  #expect(workspace.navigation.page == .library && workspace.scope == .notes)
  #expect(workspace.selectedID != nil)
  await vault.flush()
}

@Test @MainActor func vaultBackAndForwardRestoreSectionsFiltersAndDocumentWithoutStaleSelection()
  async throws
{
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  await vault.waitUntilLoaded()
  vault.suspendBackgroundProcessing()
  let header = try await vault.createDocument(
    metadata: .init(kind: .note, title: "A saved thought", modifiedAt: Date()),
    notes: "Keep this idea.")
  let workspace = VaultWorkspaceModel(vault: vault)
  workspace.resume()
  defer { workspace.stop() }
  workspace.selectScope(.notes)
  workspace.searchText = "idea"
  workspace.ordering = .oldest
  workspace.select(header.id)
  await waitForNavigationSelection(workspace, id: header.id)
  let previousQuery = workspace.query
  workspace.showStorage()
  workspace.selectScope(.trash)
  #expect(workspace.selectedID == nil && workspace.selectedIDs.isEmpty)
  workspace.goBack()
  #expect(workspace.navigation.page == .storage)
  #expect(workspace.sidebarSelection == .storage)
  workspace.goBack()
  #expect(workspace.navigation.page == .library)
  #expect(workspace.query == previousQuery)
  await waitForNavigationSelection(workspace, id: header.id)
  #expect(workspace.selectedID == header.id)
  workspace.goForward()
  #expect(workspace.navigation.page == .storage)
  workspace.goForward()
  #expect(workspace.sidebarSelection == .scope(.trash))
  #expect(workspace.selectedID == nil)
  await vault.flush()
}

@Test @MainActor func vaultEmptyWorkspaceAndStorageFillCompactAndWideLayouts() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  await vault.waitUntilLoaded()
  vault.suspendBackgroundProcessing()
  let model = SessionVaultModel(vault: vault, presentation: .init())
  model.resume()
  await model.workspace.refresh()
  defer { model.stop() }
  let column = NSHostingController(
    rootView: VaultWorkspaceList(
      model: model.workspace, export: { _ in }, canExport: true))
  let columnSize = CGSize(width: 290, height: 700)
  #expect(
    column.sizeThatFits(in: columnSize).height == columnSize.height,
    "An empty list must fill the column so its header cannot drift to the middle.")
  let root = SessionVaultView(vault: vault, conversations: nil, model: model)
  for (name, size) in [
    ("wide", SessionVaultWindowController.initialSize),
    ("compact", SessionVaultWindowController.minimumSize),
  ] {
    model.workspace.selectScope(.all)
    try await renderSettledSkillInterface(
      root.preferredColorScheme(.light), size: size,
      name: "sillies-vault-empty-\(name)")
    model.workspace.selectScope(.trash)
    model.workspace.showStorage()
    try await renderSettledSkillInterface(
      root.preferredColorScheme(.light), size: size,
      name: "sillies-vault-storage-\(name)")
    try await renderSettledSkillInterface(
      root.preferredColorScheme(.dark), size: size,
      name: "sillies-vault-storage-dark-\(name)")
  }
  await vault.flush()
}

@Test @MainActor func vaultSearchReturnsToResultsAndHistoryPreservesThePageItReplaced() async {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  await vault.waitUntilLoaded()
  vault.suspendBackgroundProcessing()
  let workspace = VaultWorkspaceModel(vault: vault)
  workspace.resume()
  defer { workspace.stop() }
  workspace.selectScope(.notes)
  workspace.updateSearchText("old query")
  workspace.showStorage()
  workspace.updateSearchText("new query")
  workspace.updateSearchText("new query extended")
  #expect(workspace.navigation.page == .library)
  #expect(workspace.sidebarSelection == .scope(.notes))
  workspace.goBack()
  #expect(workspace.navigation.page == .storage)
  #expect(workspace.searchText == "old query")
  workspace.goForward()
  #expect(workspace.navigation.page == .library)
  #expect(workspace.searchText == "new query extended")
  workspace.begin(.link)
  workspace.composeLink = "https://example.com/idea"
  workspace.selectTextMatching(.phrase)
  #expect(workspace.navigation.page == .library && workspace.textMatching == .phrase)
  workspace.goBack()
  #expect(workspace.composer == .link && workspace.textMatching == .words)
  #expect(workspace.composeLink == "https://example.com/idea")
  workspace.updateSearchText("")
  #expect(workspace.navigation.page == .library && workspace.searchText.isEmpty)
  await vault.flush()
}

@Test @MainActor func vaultReturningToLibraryResumesAnInterruptedDocumentOpen() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  await vault.waitUntilLoaded()
  vault.suspendBackgroundProcessing()
  let header = try await vault.createDocument(
    metadata: .init(kind: .note, title: "Still here", modifiedAt: Date()), notes: "Saved thought")
  let workspace = VaultWorkspaceModel(vault: vault)
  workspace.resume()
  defer { workspace.stop() }
  workspace.select(header.id)
  workspace.showStorage()
  await Task.yield()
  #expect(!workspace.isOpening && workspace.selectedID == header.id)
  workspace.showLibrary()
  await waitForNavigationSelection(workspace, id: header.id)
  #expect(workspace.document.editor.text == "Saved thought")
  workspace.begin(.link)
  workspace.showLibrary()
  await waitForNavigationSelection(workspace, id: header.id)
  #expect(workspace.document.editor.text == "Saved thought")
  await vault.flush()
}

@MainActor private func waitForNavigationSelection(_ workspace: VaultWorkspaceModel, id: UUID) async
{
  let deadline = ContinuousClock.now + .seconds(3)
  while workspace.isOpening || workspace.document.header?.id != id, ContinuousClock.now < deadline {
    await Task.yield()
  }
  #expect(!workspace.isOpening && workspace.document.header?.id == id)
}
