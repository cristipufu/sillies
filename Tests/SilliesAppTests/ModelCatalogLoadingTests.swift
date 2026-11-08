import Foundation
import SilliesModelStore
import Testing

@testable import SilliesApp

@Test @MainActor func modelCatalogRetriesIncompleteInstallationDiscoveryWithoutPublishingIt()
  async throws
{
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: root) }
  let catalog = try TextModelCatalog.bundled().manifests
  let first = try #require(catalog.first)
  let directory = root.appendingPathComponent(first.modelID).appendingPathComponent(first.revision)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let receipt = directory.appendingPathComponent("installed.json")
  try Data("Interrupted receipt".utf8).write(to: receipt)
  let model = catalogPresentation(root: root, catalog: { catalog })
  await model.load()
  #expect(model.error != nil && !model.isLoading)
  #expect(model.manifests.isEmpty && model.states.isEmpty)
  try FileManager.default.removeItem(at: receipt)
  await model.load()
  #expect(model.error == nil && !model.isLoading)
  #expect(model.manifests == catalog)
  #expect(model.states.count == catalog.count && model.states.values.allSatisfy { $0 == .absent })
  model.stop()
}

@Test @MainActor func modelCatalogJoinsDiscoveryAndRejectsResultsAfterStopAndRestart() async throws
{
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let catalog = try TextModelCatalog.bundled().manifests
  let held = HeldModelCatalog(early: Array(catalog.prefix(1)), current: Array(catalog.suffix(1)))
  let model = catalogPresentation(root: root, catalog: { await held.load() })
  model.start()
  let first = Task { await model.load() }
  let deadline = ContinuousClock.now.advanced(by: .seconds(2))
  while !(await held.isWaiting), ContinuousClock.now < deadline {
    try await Task.sleep(for: .milliseconds(5))
  }
  #expect(await held.isWaiting)
  #expect(await held.calls == 1 && model.isLoading)
  model.stop()
  await model.load()
  #expect(await held.calls == 2 && !model.isLoading)
  #expect(model.manifests == Array(catalog.suffix(1)))
  await held.release()
  await first.value
  #expect(model.manifests == Array(catalog.suffix(1)) && model.error == nil)
  model.stop()
}

@MainActor private func catalogPresentation(
  root: URL, catalog: @escaping @Sendable () async throws -> [TextModelManifest]
) -> TextModelsPresentation {
  .init(
    environment: .init(
      store: ModelStore(root: root), catalog: catalog, selectedID: { "apple" },
      select: { _ in }, remove: { _ in }, minimumMemoryGB: { $0.model.minimumMemoryGB }),
    selectedID: "apple")
}

private actor HeldModelCatalog {
  let early: [TextModelManifest]
  let current: [TextModelManifest]
  private var continuation: CheckedContinuation<Void, Never>?
  private(set) var calls = 0
  var isWaiting: Bool { continuation != nil }
  init(early: [TextModelManifest], current: [TextModelManifest]) {
    self.early = early
    self.current = current
  }
  func load() async -> [TextModelManifest] {
    calls += 1
    guard calls == 1 else { return current }
    await withCheckedContinuation { continuation = $0 }
    return early
  }
  func release() {
    continuation?.resume()
    continuation = nil
  }
}
