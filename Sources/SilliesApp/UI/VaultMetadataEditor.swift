import Foundation
import Observation
import SilliesCore

/// Owns title/tag drafts and drains saves through the native termination run loop.
@MainActor @Observable final class VaultMetadataEditor {
  private static let saveDelay: Duration = .milliseconds(450)
  private let vault: SessionVaultStore
  private var baseline: VaultDocumentHeader?
  private var loading = false
  var title = "" { didSet { changed() } }
  var tags = "" { didSet { changed() } }
  private(set) var error: String?
  private(set) var isSaving = false
  private(set) var recoverySaved = false
  @ObservationIgnored private var delay: Task<Void, Never>?
  @ObservationIgnored private var completions: [@MainActor () -> Void] = []
  @ObservationIgnored private var flusherID: UUID?
  var canNavigate: Bool { !isDirty || recoverySaved }
  var isDirty: Bool { draft != nil }
  private var parsedTags: [String] {
    Array(
      Set(
        tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter
        { !$0.isEmpty })
    ).sorted()
  }
  private var draft: VaultMetadataDraft? {
    guard let baseline else { return nil }
    let title = title == baseline.title ? nil : title
    let tags = parsedTags == baseline.metadata.tags ? nil : parsedTags
    guard title != nil || tags != nil else { return nil }
    return .init(recordID: baseline.id, title: title, tags: tags)
  }

  init(vault: SessionVaultStore) {
    self.vault = vault
    flusherID = vault.registerDraftFlusher { [weak self] done in
      guard let self else {
        done()
        return
      }
      self.flush(completion: done)
    }
  }

  func load(_ header: VaultDocumentHeader?, recovered: VaultMetadataDraft?) {
    loading = true
    baseline = header
    title = recovered?.title ?? header?.title ?? ""
    tags = (recovered?.tags ?? header?.metadata.tags ?? []).joined(separator: ", ")
    recoverySaved = recovered != nil
    error = nil
    loading = false
  }

  func refresh(_ header: VaultDocumentHeader) {
    guard baseline?.id == header.id else { return }
    let pending = draft
    loading = true
    baseline = header
    if pending?.title == nil { title = header.title }
    if pending?.tags == nil { tags = header.metadata.tags.joined(separator: ", ") }
    loading = false
  }

  private func changed() {
    guard !loading else { return }
    recoverySaved = false
    error = nil
    delay?.cancel()
    delay = Task { [weak self] in
      do { try await Task.sleep(for: Self.saveDelay) } catch { return }
      await self?.flush()
    }
  }

  func flush() async {
    await withCheckedContinuation { continuation in flush { continuation.resume() } }
  }
  func flush(completion: @escaping @MainActor () -> Void) {
    delay?.cancel()
    delay = nil
    completions.append(completion)
    guard !isSaving else { return }
    save()
  }

  private func save() {
    guard let draft, error == nil else {
      finish()
      return
    }
    isSaving = true
    Task.detached { [self, library = vault.library] in
      var recovered = false
      let result: Result<VaultDocumentHeader, Error>
      do {
        try await library.saveMetadataDraft(draft)
        recovered = true
        result = .success(try await library.commitMetadataDraft(draft, at: Date()))
      } catch { result = .failure(error) }
      let persisted = recovered
      MainRunLoopDelivery.perform { self.receive(result, draft: draft, persisted: persisted) }
    }
  }

  private func receive(
    _ result: Result<VaultDocumentHeader, Error>, draft: VaultMetadataDraft, persisted: Bool
  ) {
    isSaving = false
    switch result {
    case .success(let header):
      if let flusherID { vault.reportDraftFailure(nil, owner: flusherID) }
      loading = true
      if title == draft.title { title = header.title }
      if parsedTags == draft.tags { tags = header.metadata.tags.joined(separator: ", ") }
      baseline = header
      loading = false
      vault.workspaceChanged([header.id])
      recoverySaved = !isDirty
      error = nil
      save()
    case .failure(let failure):
      recoverySaved =
        persisted && self.draft?.title == draft.title && self.draft?.tags == draft.tags
      error = failure.localizedDescription
      if let flusherID { vault.reportDraftFailure(recoverySaved ? nil : error, owner: flusherID) }
      fputs("Vault metadata save failed: \(failure)\n", stderr)
      finish()
    }
  }

  private func finish() {
    isSaving = false
    let waiting = completions
    completions.removeAll()
    for done in waiting { done() }
  }

  func stop() {
    delay?.cancel()
    flush {}
  }
  func retry() async {
    error = nil
    await flush()
  }
  isolated deinit {
    delay?.cancel()
    if let flusherID { vault.unregisterDraftFlusher(flusherID) }
  }
}
