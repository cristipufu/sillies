import Foundation
import ImageIO
import SilliesCore

/// Site previews use Apple's native metadata loader; no remote HTML is rendered in the Vault.
actor SystemVaultLinkPreviewFetcher: VaultLinkPreviewFetching {
  private static let maximumImageBytes = 8 * 1_024 * 1_024
  private static let imagePixels = 640
  private static let timeout: TimeInterval = 18

  func fetch(_ link: VaultLink) async throws -> VaultLinkPreview {
    var updated = link
    if link.kind != .website {
      do { updated = try await VaultOEmbedClient().fetch(link) } catch is CancellationError {
        throw CancellationError()
      } catch {
        fputs("Official link preview unavailable; trying native metadata.\n", stderr)
      }
    }
    let result: NativeLinkMetadataTask.Result
    do {
      result = try await NativeLinkMetadataTask.fetch(link.url, timeout: Self.timeout)
    } catch is CancellationError { throw CancellationError() } catch {
      if updated.previewState == .available { return .init(link: updated) }
      throw error
    }
    try Task.checkCancellation()
    if updated.previewState != .available, let title = result.title, !title.isEmpty {
      updated.title = String(title.prefix(1_024))
    }
    updated.previewState = .available
    updated.fetchedAt = Date()
    let image = result.image.flatMap(Self.thumbnail)
    return .init(link: updated, image: image)
  }

  private static func thumbnail(_ data: Data) -> Data? {
    guard data.count <= maximumImageBytes,
      let source = CGImageSourceCreateWithData(
        data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
    else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceThumbnailMaxPixelSize: imagePixels,
      kCGImageSourceCreateThumbnailWithTransform: true,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
      return nil
    }
    return VaultImageCodec.encodePNGData(from: image)
  }
}
