import Foundation

/// A saved URL remains useful when a site cannot provide a preview or is no longer available.
public struct VaultLink: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, Sendable { case website, post, video }
  public enum PreviewState: String, Codable, Sendable { case pending, available, unavailable }
  public let url: URL
  public let kind: Kind
  public let sourceID: String?
  public var title: String
  public var author: String
  public var description: String
  public var imageFilename: String?
  public var previewState: PreviewState
  public var fetchedAt: Date?

  public init(url: URL) throws {
    guard let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
      let host = url.host, !host.isEmpty, url.user == nil, url.password == nil
    else { throw VaultLinkError.invalidURL }
    self.url = url
    let identity = Self.identity(of: url)
    kind = identity.kind
    sourceID = identity.id
    title = host
    author = ""
    description = ""
    previewState = .pending
  }

  private static func identity(of url: URL) -> (kind: Kind, id: String?) {
    let host = url.host?.lowercased() ?? ""
    let parts = url.pathComponents.filter { $0 != "/" }
    if ["x.com", "www.x.com", "twitter.com", "www.twitter.com", "mobile.twitter.com"].contains(
      host),
      let status = parts.firstIndex(of: "status"), status + 1 < parts.count
    {
      let id = parts[status + 1]
      if !id.isEmpty, id.utf8.allSatisfy({ (48...57).contains($0) }) { return (.post, id) }
    }
    let videoID: String?
    if host == "youtu.be" || host == "www.youtu.be" {
      videoID = parts.first
    } else if ["youtube.com", "www.youtube.com", "m.youtube.com"].contains(host) {
      if let first = parts.first, ["shorts", "live", "embed"].contains(first), parts.count > 1 {
        videoID = parts[1]
      } else {
        videoID =
          URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
          .first(where: { $0.name == "v" })?.value
      }
    } else {
      videoID = nil
    }
    if let videoID, videoID.utf8.count == 11,
      videoID.utf8.allSatisfy({
        (48...57).contains($0) || (65...90).contains($0)
          || (97...122).contains($0) || $0 == 45 || $0 == 95
      })
    {
      return (.video, videoID)
    }
    return (.website, nil)
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(url: values.decode(URL.self, forKey: .url))
    title = try values.decode(String.self, forKey: .title)
    author = try values.decode(String.self, forKey: .author)
    description = try values.decode(String.self, forKey: .description)
    imageFilename = try values.decodeIfPresent(String.self, forKey: .imageFilename)
    previewState = try values.decode(PreviewState.self, forKey: .previewState)
    fetchedAt = try values.decodeIfPresent(Date.self, forKey: .fetchedAt)
    guard title.unicodeScalars.count <= 1_024, author.unicodeScalars.count <= 256,
      description.unicodeScalars.count <= 8_192
    else { throw VaultEditingError.invalidValue }
  }
}

extension VaultLink: SessionAttachmentReference { public var audioFilename: String? { nil } }

public enum VaultLinkError: Error, LocalizedError {
  case invalidURL
  public var errorDescription: String? {
    String(localized: "Enter a complete http or https link without a username or password.")
  }
}
