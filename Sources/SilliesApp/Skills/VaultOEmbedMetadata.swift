import Foundation
import SilliesCore

/// Provider-owned preview fields are replaced on refresh; the document owns any custom user title.
struct VaultOEmbedMetadata: Decodable, Sendable {
  private static let maximumTitleCharacters = 1_024
  private static let maximumAuthorCharacters = 256
  private static let maximumDescriptionCharacters = 8_192
  private static let excerptTitleCharacters = 120

  let title: String?
  let authorName: String?
  let html: String?

  private enum CodingKeys: String, CodingKey {
    case title, html
    case authorName = "author_name"
  }

  func preview(for link: VaultLink, fetchedAt: Date) -> VaultLink {
    var updated = link
    updated.author = String((authorName ?? "").prefix(Self.maximumAuthorCharacters))
    if link.kind == .post, let html {
      updated.description = String(
        VaultHTMLExcerpt.text(html).prefix(Self.maximumDescriptionCharacters))
    }
    if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      updated.title = String(title.prefix(Self.maximumTitleCharacters))
    } else if link.kind == .post, !updated.description.isEmpty {
      updated.title = String(updated.description.prefix(Self.excerptTitleCharacters))
    }
    updated.previewState = .available
    updated.fetchedAt = fetchedAt
    return updated
  }
}
