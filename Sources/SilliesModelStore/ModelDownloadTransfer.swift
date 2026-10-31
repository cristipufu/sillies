import Foundation
import Synchronization

/// Explicit download tasks deliver byte callbacks that URLSession's async convenience API omits.
final class ModelDownloadTransfer: NSObject, URLSessionDownloadDelegate {
  private enum Cancellation {
    case none, waiting
    case received(Data?)
  }
  private struct State {
    var continuation: CheckedContinuation<URL, any Error>?
    var file: Result<URL, any Error>?
    var completed = false
    var cancellation = Cancellation.none
    var lastProgress: TimeInterval = 0
  }
  private static let progressInterval: TimeInterval = 0.1
  private let request: ModelDownloadRequest
  private let state = Mutex(State())

  init(request: ModelDownloadRequest) { self.request = request }

  func run(_ task: URLSessionDownloadTask) async throws -> URL {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        state.withLock { $0.continuation = continuation }
        task.resume()
        finishIfReady()
      }
    } onCancel: {
      self.state.withLock { $0.cancellation = .waiting }
      task.cancel { data in
        self.state.withLock { $0.cancellation = .received(data) }
        self.finishIfReady()
      }
    }
  }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    let result = Result {
      guard let response = downloadTask.response as? HTTPURLResponse,
        [200, 206].contains(response.statusCode),
        let size = try location.resourceValues(forKeys: [.fileSizeKey]).fileSize,
        Int64(size) == request.artifact.byteCount
      else { throw ModelStoreError.invalidArtifact(request.artifact.path) }
      // URLSession deletes its temporary file when this callback returns.
      let retained = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString)
      try FileManager.default.moveItem(at: location, to: retained)
      return retained
    }
    state.withLock { $0.file = result }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    state.withLock { state in
      if state.file == nil {
        state.file = .failure(error ?? ModelStoreError.invalidArtifact(request.artifact.path))
      }
      state.completed = true
    }
    finishIfReady()
  }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
  ) {
    guard totalBytesWritten <= request.artifact.byteCount else {
      state.withLock { $0.file = .failure(ModelStoreError.invalidArtifact(request.artifact.path)) }
      downloadTask.cancel()
      return
    }
    let now = ProcessInfo.processInfo.systemUptime
    let publish = state.withLock { state in
      guard
        now - state.lastProgress >= Self.progressInterval
          || totalBytesWritten == request.artifact.byteCount
      else { return false }
      state.lastProgress = now
      return true
    }
    if publish { request.progress(totalBytesWritten) }
  }

  private func finishIfReady() {
    let completion = state.withLock { state -> (() -> Void)? in
      guard state.completed, let file = state.file, let continuation = state.continuation else {
        return nil
      }
      let result: Result<URL, any Error>
      switch state.cancellation {
      case .waiting: return nil
      case .none: result = file
      case .received(let data):
        let info: [String: Any] = data.map { [NSURLSessionDownloadTaskResumeData: $0] } ?? [:]
        result = .failure(
          NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled, userInfo: info))
      }
      state.continuation = nil
      return {
        if case .failure = result, case .success(let temporary) = file {
          do { try FileManager.default.removeItem(at: temporary) } catch { ModelFiles.log(error) }
        }
        continuation.resume(with: result)
      }
    }
    completion?()
  }
}
