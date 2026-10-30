import Foundation
import Synchronization

package struct ModelDownloadRequest: Sendable {
  package let artifact: ModelArtifact
  package let resumeFile: URL
  package let progress: @Sendable (Int64) -> Void
}

package protocol ModelDownloading: Sendable {
  func download(_ request: ModelDownloadRequest) async throws -> URL
}

package struct ModelDownloadClient: ModelDownloading {
  package init() {}

  package func download(_ request: ModelDownloadRequest) async throws -> URL {
    let delegate = DownloadProgress(
      expectedBytes: request.artifact.byteCount, update: request.progress)
    let session = URLSession(configuration: .ephemeral)
    defer { session.invalidateAndCancel() }
    do {
      let result: (URL, URLResponse)
      if FileManager.default.fileExists(atPath: request.resumeFile.path) {
        let resumeData = try Data(contentsOf: request.resumeFile)
        result = try await session.download(resumeFrom: resumeData, delegate: delegate)
      } else {
        result = try await session.download(from: request.artifact.url, delegate: delegate)
      }
      guard let response = result.1 as? HTTPURLResponse, [200, 206].contains(response.statusCode)
      else {
        throw ModelStoreError.invalidArtifact(request.artifact.path)
      }
      if FileManager.default.fileExists(atPath: request.resumeFile.path) {
        try FileManager.default.removeItem(at: request.resumeFile)
      }
      return result.0
    } catch {
      if let data = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
        do { try data.write(to: request.resumeFile, options: .atomic) } catch {
          ModelFiles.log(error)
        }
      } else if FileManager.default.fileExists(atPath: request.resumeFile.path) {
        do { try FileManager.default.removeItem(at: request.resumeFile) } catch {
          ModelFiles.log(error)
        }
      }
      throw error
    }
  }
}

private final class DownloadProgress: NSObject, URLSessionDownloadDelegate {
  private static let interval: TimeInterval = 0.1
  private let expectedBytes: Int64
  private let update: @Sendable (Int64) -> Void
  private let lastUpdate = Mutex<TimeInterval>(0)

  init(expectedBytes: Int64, update: @escaping @Sendable (Int64) -> Void) {
    self.expectedBytes = expectedBytes
    self.update = update
  }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {}

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
  ) {
    guard totalBytesWritten <= expectedBytes else {
      downloadTask.cancel()
      return
    }
    let now = ProcessInfo.processInfo.systemUptime
    let shouldPublish = lastUpdate.withLock { previous in
      guard now - previous >= Self.interval || totalBytesWritten == expectedBytes else {
        return false
      }
      previous = now
      return true
    }
    if shouldPublish { update(totalBytesWritten) }
  }
}
