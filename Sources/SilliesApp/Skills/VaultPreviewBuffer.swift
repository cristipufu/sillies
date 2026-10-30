import CoreGraphics
import Synchronization

/// Stages decoded images for main-run-loop delivery, including modal termination.
final class VaultPreviewBuffer: Sendable {
  typealias Entry = (filename: String, image: CGImage)
  private let entries = Mutex<[Entry]>([])

  func append(filename: String, image: CGImage) {
    entries.withLock { $0.append((filename, image)) }
  }

  func remove(filename: String) { entries.withLock { $0.removeAll { $0.filename == filename } } }

  func removeAll() { entries.withLock { $0.removeAll() } }

  func drain() -> [Entry] {
    entries.withLock {
      let drained = $0
      $0.removeAll()
      return drained
    }
  }
}
