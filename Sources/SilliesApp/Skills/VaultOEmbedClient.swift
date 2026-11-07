import Foundation
import SilliesCore

/// Official public preview endpoints enrich saved posts and videos without executing embed scripts.
struct VaultOEmbedClient: Sendable {
  private static let maximumResponseBytes = 256 * 1_024
  private static let timeout: TimeInterval = 15

  func fetch(_ link: VaultLink) async throws -> VaultLink {
    guard let endpoint = endpoint(for: link) else { return link }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = Self.timeout
    configuration.timeoutIntervalForResource = Self.timeout
    configuration.httpCookieStorage = nil
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let (bytes, response) = try await session.bytes(from: endpoint)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
      response.expectedContentLength <= Self.maximumResponseBytes
    else { throw URLError(.badServerResponse) }
    var data = Data()
    for try await byte in bytes {
      try Task.checkCancellation()
      guard data.count < Self.maximumResponseBytes else {
        throw URLError(.dataLengthExceedsMaximum)
      }
      data.append(byte)
    }
    return try JSONDecoder().decode(VaultOEmbedMetadata.self, from: data)
      .preview(for: link, fetchedAt: Date())
  }

  private func endpoint(for link: VaultLink) -> URL? {
    var components = URLComponents()
    components.scheme = "https"
    components.path = "/oembed"
    switch link.kind {
    case .website: return nil
    case .post: components.host = "publish.x.com"
    case .video: components.host = "www.youtube.com"
    }
    components.queryItems = [
      .init(name: "url", value: link.url.absoluteString), .init(name: "format", value: "json"),
      .init(name: "omit_script", value: "true"),
    ]
    return components.url
  }
}
