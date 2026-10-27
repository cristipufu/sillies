import Foundation
import Testing

func removeTestFile(at url: URL) {
  guard FileManager.default.fileExists(atPath: url.path) else { return }
  do {
    try FileManager.default.removeItem(at: url)
  } catch {
    let message = "Test cleanup failed for \(url.lastPathComponent): \(error.localizedDescription)"
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    Issue.record(error, Comment(rawValue: message))
  }
}
