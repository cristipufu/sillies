import Foundation
import Observation
import SilliesCore
import SilliesPersistence
import SilliesVault

/// Owns cancellable keyword and meaning reads; navigation and document editing have separate lifetimes.
@MainActor @Observable final class VaultWorkspaceSearch {
  private static let debounce: Duration = .milliseconds(140)
  private static let maximumRememberedPages = 100
  private let vault: SessionVaultStore
  private(set) var records: [VaultDocumentHeader] = []
  private var semanticRecords: [VaultDocumentHeader] = []
  private var semanticQuery: VaultWorkspaceQuery?
  private(set) var isFindingRelated = false
  private(set) var meaningAvailability: VaultRelatedSearchResult.Availability?
  private(set) var isLoading = false
  private(set) var error: String?
  private(set) var pageNumber = 0
  private(set) var hasMore = false
  private(set) var appliedQuery: VaultWorkspaceQuery?
  private var appliedRevision: Int?
  private var cursors: [VaultWorkspaceCursor?] = [nil]
  private var firstPageNumber = 0
  var canRetreat: Bool { pageNumber > firstPageNumber }
  private var nextCursor: VaultWorkspaceCursor?
  private var generation = UUID()
  private var isPresented = false
  @ObservationIgnored private var semanticTask: Task<Void, Never>?
  @ObservationIgnored private var keywordTask: Task<VaultWorkspacePage, Error>?

  init(vault: SessionVaultStore) { self.vault = vault }
  func resume() { isPresented = true }
  func stop() {
    isPresented = false
    generation = UUID()
    semanticTask?.cancel()
    keywordTask?.cancel()
    isLoading = false
    isFindingRelated = false
  }
  func related(to query: VaultWorkspaceQuery) -> [VaultDocumentHeader] {
    guard semanticQuery == query else { return [] }
    let listed = appliedQuery == query ? Set(records.map(\.id)) : []
    return semanticRecords.filter { !listed.contains($0.id) }
  }
  func advance() -> Bool {
    guard let nextCursor, !isLoading else { return false }
    cursors = Array(cursors.prefix(pageNumber - firstPageNumber + 1)) + [nextCursor]
    pageNumber += 1
    if cursors.count > Self.maximumRememberedPages {
      cursors.removeFirst()
      firstPageNumber += 1
    }
    return true
  }
  func retreat() -> Bool {
    guard canRetreat, !isLoading else { return false }
    pageNumber -= 1
    return true
  }
  func refresh(_ request: VaultWorkspaceQuery) async -> Bool {
    guard isPresented else { return false }
    let token = UUID()
    generation = token
    semanticTask?.cancel()
    keywordTask?.cancel()
    if appliedQuery != request
      || (request.ordering == .relevance && appliedRevision != vault.searchRevision)
    {
      cursors = [nil]
      pageNumber = 0
      firstPageNumber = 0
      semanticRecords = []
      nextCursor = nil
      hasMore = false
    }
    meaningAvailability = nil
    isFindingRelated = false
    isLoading = true
    defer {
      if generation == token {
        isLoading = false
        keywordTask = nil
      }
    }
    do {
      if !request.text.isEmpty { try await Task.sleep(for: Self.debounce) }
      await vault.waitUntilLoaded()
      guard generation == token, isPresented, !Task.isCancelled else { return false }
      enrichSearch(request, generation: token)
      let cursor = cursors[pageNumber - firstPageNumber]
      let task = Task { [library = vault.library] in
        try await library.workspacePage(request, after: cursor)
      }
      keywordTask = task
      let page = try await withTaskCancellationHandler(
        operation: { try await task.value }, onCancel: { task.cancel() })
      guard generation == token, isPresented, !Task.isCancelled else { return false }
      records = page.records
      nextCursor = page.next
      hasMore = page.next != nil
      appliedQuery = request
      appliedRevision = vault.searchRevision
      error = nil
      return true
    } catch is CancellationError { return false } catch {
      guard generation == token, isPresented, !Task.isCancelled else { return false }
      self.error = error.localizedDescription
      return false
    }
  }

  private func enrichSearch(_ query: VaultWorkspaceQuery, generation: UUID) {
    meaningAvailability = nil
    isFindingRelated = false
    guard !query.text.isEmpty, query.scope != .trash,
      query.textMatching == nil || query.textMatching == .words
    else { return }
    isFindingRelated = true
    semanticTask = Task { [weak self, vault] in
      defer { if self?.generation == generation { self?.isFindingRelated = false } }
      do {
        let result = try await vault.library.relatedSearch(.init(workspace: query))
        var headers: [VaultDocumentHeader] = []
        for match in result.matches {
          try Task.checkCancellation()
          guard let header = try await vault.library.documentHeader(id: match.header.id),
            header.metadata.trashedAt == nil
          else { continue }
          if Self.includes(header, in: query) {
            headers.append(
              .init(
                source: header.source, metadata: header.metadata, excerpt: match.excerpt,
                match: match.location))
          }
        }
        guard let self, self.generation == generation, self.isPresented, !Task.isCancelled else {
          return
        }
        self.semanticRecords = headers
        self.semanticQuery = query
        self.meaningAvailability = result.availability
      } catch is CancellationError { return } catch {
        fputs("Vault related search failed: \(error)\n", stderr)
        guard self?.generation == generation, !Task.isCancelled else { return }
        self?.meaningAvailability = .failed(error.localizedDescription)
      }
    }
  }

  private static func includes(_ header: VaultDocumentHeader, in query: VaultWorkspaceQuery) -> Bool
  {
    if query.source?.includes(header.source) == false { return false }
    if let from = query.from, header.source.createdAt < from { return false }
    if let until = query.until, header.source.createdAt >= until { return false }
    if let kind = query.kind, header.source.kind != kind { return false }
    if let collection = query.collectionID, !header.metadata.collectionIDs.contains(collection) {
      return false
    }
    if let tag = query.tag, !header.metadata.tags.contains(tag) { return false }
    switch query.scope {
    case .all: return true
    case .starred: return header.metadata.isStarred || header.source.isProtected
    case .notes: return header.metadata.kind == .note
    case .meetings: return [.listen, .participate, .record].contains(header.source.kind)
    case .screenshots: return header.source.imageFilename != nil
    case .links:
      return header.metadata.kind == .link
        || (header.source.kind == .stash && header.metadata.kind == .capture)
    case .conversations, .trash: return false
    }
  }

}
