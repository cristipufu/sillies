import Foundation
import UniformTypeIdentifiers

/// Item providers may never deliver a callback. Timeout and cancellation finish the request once.
@MainActor final class NativeLinkImageRequest {
  private static let timeout: Duration = .seconds(5)
  nonisolated private static let maximumBytes = 8 * 1_024 * 1_024
  private var continuation: CheckedContinuation<Data?, Never>?
  private var progress: Progress?
  private var timeoutTask: Task<Void, Never>?

  func load(_ provider: NSItemProvider?) async -> Data? {
    guard let provider, provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
      return nil
    }
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        guard !Task.isCancelled else {
          continuation.resume(returning: nil)
          return
        }
        self.continuation = continuation
        progress = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) {
          [weak self] data, _ in
          let bounded = data.flatMap { $0.count <= Self.maximumBytes ? $0 : nil }
          Task { @MainActor [weak self] in self?.finish(bounded) }
        }
        timeoutTask = Task { [weak self] in
          do { try await Task.sleep(for: Self.timeout) } catch { return }
          self?.finish(nil)
        }
      }
    } onCancel: {
      Task { @MainActor [weak self] in self?.finish(nil) }
    }
  }

  private func finish(_ data: Data?) {
    guard let continuation else { return }
    self.continuation = nil
    timeoutTask?.cancel()
    timeoutTask = nil
    progress?.cancel()
    progress = nil
    continuation.resume(returning: data)
  }
}
