import Foundation

public struct VaultLinkPreview: Sendable {
  public let link: VaultLink
  public let image: Data?
  public init(link: VaultLink, image: Data? = nil) {
    self.link = link
    self.image = image
  }
}

public protocol VaultLinkPreviewFetching: Sendable {
  func fetch(_ link: VaultLink) async throws -> VaultLinkPreview
}
