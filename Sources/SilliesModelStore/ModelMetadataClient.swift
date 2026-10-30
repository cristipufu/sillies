import Foundation

package protocol ModelMetadataFetching: Sendable {
  func fetch(_ url: URL, maximumBytes: Int) async throws -> Data
}

/// Bounded metadata requests never download model weights or use ambient credentials.
package struct ModelMetadataClient: ModelMetadataFetching {
  package init() {}
  package func fetch(_ url: URL, maximumBytes: Int) async throws -> Data {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 20
    configuration.timeoutIntervalForResource = 30
    configuration.httpCookieStorage = nil
    configuration.urlCredentialStorage = nil
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let (bytes, response) = try await session.bytes(from: url)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200,
      response.expectedContentLength <= maximumBytes
    else { throw ModelUpdateError.metadataUnavailable }
    var data = Data()
    for try await byte in bytes {
      try Task.checkCancellation()
      guard data.count < maximumBytes else { throw ModelUpdateError.metadataTooLarge }
      data.append(byte)
    }
    return data
  }
}
