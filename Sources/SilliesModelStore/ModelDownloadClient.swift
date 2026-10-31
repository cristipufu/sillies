import Foundation

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
    try Task.checkCancellation()
    let delegate = ModelDownloadTransfer(request: request)
    let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
    defer { session.invalidateAndCancel() }
    do {
      let task: URLSessionDownloadTask
      if FileManager.default.fileExists(atPath: request.resumeFile.path) {
        let resumeData = try Data(contentsOf: request.resumeFile)
        task = session.downloadTask(withResumeData: resumeData)
      } else {
        task = session.downloadTask(with: request.artifact.url)
      }
      let file = try await delegate.run(task)
      if FileManager.default.fileExists(atPath: request.resumeFile.path) {
        do { try FileManager.default.removeItem(at: request.resumeFile) } catch {
          ModelFiles.log(error)
        }
      }
      return file
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
