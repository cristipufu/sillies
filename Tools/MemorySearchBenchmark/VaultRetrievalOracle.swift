import Foundation
import SilliesCore
import SilliesVault

/// Exact scoring through the same application API, with approximate candidates disabled.
actor VaultRetrievalOracle {
  private let library: VaultLibrary

  private init(library: VaultLibrary) { self.library = library }

  static func make(directory: URL, access: SearchEmbeddingAccess) async throws
    -> VaultRetrievalOracle
  {
    let library = VaultLibrary(directory: directory, cacheBytes: 0)
    _ = try await library.snapshot()
    try await library.useSearchEmbeddings(.init(identity: access.identity, embed: access.embed))
    return VaultRetrievalOracle(library: library)
  }

  func search(_ request: VaultSearchRequest) async throws -> VaultRelatedSearchResult {
    try await library.relatedSearch(request)
  }

  func stop() async throws { try await library.useSearchEmbeddings(nil) }
}
