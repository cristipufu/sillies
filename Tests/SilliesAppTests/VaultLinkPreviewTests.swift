import Foundation
import SilliesCore
import SilliesVault
import Testing

@testable import SilliesApp

@Test func vaultOEmbedRefreshReplacesCachedTitlesWhilePreservingCustomDocumentTitles() async throws
{
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let library = VaultLibrary(directory: directory)
  _ = try await library.snapshot()
  var cached = try VaultLink(url: #require(URL(string: "https://x.com/example/status/123")))
  cached.title = "Old &mdash; cached title"
  cached.previewState = .available
  let response = try JSONDecoder().decode(
    VaultOEmbedMetadata.self,
    from: Data(
      #"{"author_name":"Example","html":"<blockquote><p>A new idea &mdash; caf&eacute;.</p>&mdash; Example</blockquote>"}"#
        .utf8))
  let fetchedAt = Date(timeIntervalSince1970: 42)
  let refreshed = response.preview(for: cached, fetchedAt: fetchedAt)
  let expected = "A new idea — café.\n— Example"
  #expect(refreshed.title == expected && refreshed.description == expected)
  #expect(refreshed.author == "Example" && refreshed.fetchedAt == fetchedAt)
  #expect(refreshed.url == cached.url && refreshed.sourceID == cached.sourceID)
  for title in [cached.title, "My own title"] {
    var metadata = VaultDocumentMetadata(kind: .link, title: title, modifiedAt: fetchedAt)
    metadata.link = cached
    let record = SessionRecord(
      kind: .stash,
      origin: .init(characterID: "vault", characterName: "", source: .init(appName: "Fixture")))
    _ = try await library.createDocument(record: record, metadata: metadata)
    let saved = try await library.saveLinkPreview(.init(link: refreshed), id: record.id)
    #expect(saved?.title == (title == cached.title ? expected : title))
    #expect(saved?.metadata.link?.description == expected)
  }
}

private actor SuspendedLinkPreview: VaultLinkPreviewFetching {
  private var pending: CheckedContinuation<VaultLinkPreview, Never>?
  private var link: VaultLink?
  private(set) var calls = 0
  func fetch(_ link: VaultLink) async throws -> VaultLinkPreview {
    calls += 1
    self.link = link
    return await withCheckedContinuation { pending = $0 }
  }
  func finish(title: String) {
    guard var link, let pending else { return }
    self.pending = nil
    link.title = title
    link.previewState = .available
    pending.resume(returning: .init(link: link))
  }
}

@Test @MainActor func vaultPreviewRetainsItsSlotUntilCancelledFetchingActuallyReturns() async throws
{
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let library = VaultLibrary(directory: directory)
  _ = try await library.snapshot()
  let record = SessionRecord(
    kind: .stash,
    origin: .init(characterID: "vault", characterName: "", source: .init(appName: "Fixture")))
  var metadata = VaultDocumentMetadata(kind: .link, modifiedAt: Date())
  metadata.link = try VaultLink(url: #require(URL(string: "https://example.org/reference")))
  metadata.title = metadata.link?.title ?? ""
  _ = try await library.createDocument(record: record, metadata: metadata)
  let fetcher = SuspendedLinkPreview()
  let coordinator = VaultLinkPreviewCoordinator(library: library, fetcher: fetcher)
  var deliveries = 0
  coordinator.changed = { _ in deliveries += 1 }
  coordinator.pump()
  try await waitForPreview { await fetcher.calls == 1 }
  coordinator.stop()
  coordinator.resume()
  for _ in 0..<20 { await Task.yield() }
  #expect(await fetcher.calls == 1)
  await fetcher.finish(title: "Cancelled preview")
  try await waitForPreview { await fetcher.calls == 2 }
  #expect(deliveries == 0)
  await fetcher.finish(title: "Current preview")
  try await waitForPreview { deliveries == 1 }
  #expect(try await library.documentHeader(id: record.id)?.title == "Current preview")
  coordinator.stop()
}

@Test @MainActor func nativeLinkImageCancellationDoesNotWaitForAnUnresponsiveProvider() async {
  let provider = NSItemProvider()
  provider.registerDataRepresentation(forTypeIdentifier: "public.image", visibility: .all) { _ in
    Progress(totalUnitCount: 1)
  }
  let request = NativeLinkImageRequest()
  let task = Task { await request.load(provider) }
  await Task.yield()
  task.cancel()
  #expect(await task.value == nil)
}

@MainActor private func waitForPreview(_ predicate: () async -> Bool) async throws {
  let deadline = ContinuousClock.now.advanced(by: .seconds(3))
  while !(await predicate()) {
    guard ContinuousClock.now < deadline else { throw CocoaError(.executableRuntimeMismatch) }
    await Task.yield()
  }
}
