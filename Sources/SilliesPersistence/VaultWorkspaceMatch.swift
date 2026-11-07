import SilliesCore

/// Keeps each bounded search result's source, cursor and excerpt identity together.
struct VaultWorkspaceMatch {
  let header: VaultDocumentHeader
  let position: Double
  let blockID: Int64

  func excerpt(_ text: String) -> VaultDocumentHeader {
    .init(
      source: header.source, metadata: header.metadata, excerpt: text, match: header.match
    ).timed(at: header.matchSeconds)
  }
}
