import Foundation
import LinkPresentation

@MainActor final class NativeLinkMetadataTask {
  struct Result: Sendable {
    let title: String?
    let image: Data?
  }
  private let provider = LPMetadataProvider()
  private init(timeout: TimeInterval) { provider.timeout = timeout }

  static func fetch(_ url: URL, timeout: TimeInterval) async throws -> Result {
    let task = NativeLinkMetadataTask(timeout: timeout)
    return try await withTaskCancellationHandler {
      let metadata = try await task.provider.startFetchingMetadata(for: url)
      try Task.checkCancellation()
      let image = await NativeLinkImageRequest().load(metadata.imageProvider)
      try Task.checkCancellation()
      return .init(title: metadata.title, image: image)
    } onCancel: {
      Task { @MainActor in task.provider.cancel() }
    }
  }
}
