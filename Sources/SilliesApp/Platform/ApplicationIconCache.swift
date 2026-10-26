import AppKit
import Observation
import SilliesCore

/// Views only read prepared images. LaunchServices access and image decoding run off the UI thread.
@MainActor @Observable
final class ApplicationIconCache {
  static let shared = ApplicationIconCache()
  typealias Loader = @Sendable (Int32) async -> CGImage?

  private struct Key: Hashable {
    let processID: Int32
    let bundleIdentifier: String?
  }
  private struct Entry { let image: NSImage? }
  private var entries: [Key: Entry] = [:]
  @ObservationIgnored private var pending: [Key: Task<Void, Never>] = [:]
  @ObservationIgnored private var insertionOrder: [Key] = []
  @ObservationIgnored private var generation = 0
  @ObservationIgnored private let load: Loader
  private static let capacity = 48

  init(load: Loader? = nil) {
    self.load = load ?? { await ApplicationIconLoader.shared.load(processID: $0) }
  }

  func image(for target: WindowTargetCandidate) -> NSImage? {
    entries[Key(processID: target.processID, bundleIdentifier: target.bundleIdentifier)]?.image
  }

  func prepare(for target: WindowTargetCandidate) {
    let key = Key(processID: target.processID, bundleIdentifier: target.bundleIdentifier)
    guard entries[key] == nil, pending[key] == nil else { return }
    let token = generation
    let loader = load
    pending[key] = Task { [weak self] in
      let pixels = await loader(target.processID)
      guard !Task.isCancelled, let self, self.generation == token else { return }
      self.pending.removeValue(forKey: key)
      if self.insertionOrder.count >= Self.capacity {
        self.entries.removeValue(forKey: self.insertionOrder.removeFirst())
      }
      self.entries[key] = Entry(
        image: pixels.map {
          NSImage(cgImage: $0, size: NSSize(width: 32, height: 32))
        })
      self.insertionOrder.append(key)
    }
  }

  func cancelPending() {
    generation += 1
    for task in pending.values { task.cancel() }
    pending.removeAll()
  }
}

private actor ApplicationIconLoader {
  static let shared = ApplicationIconLoader()

  func load(processID: Int32) -> CGImage? {
    dispatchPrecondition(condition: .notOnQueue(.main))
    guard !Task.isCancelled else { return nil }
    return autoreleasepool {
      guard let image = NSRunningApplication(processIdentifier: processID)?.icon else { return nil }
      let bounds = CGRect(x: 0, y: 0, width: 64, height: 64)
      var proposed = bounds
      guard let original = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil),
        let context = CGContext(
          data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return nil }
      context.draw(original, in: bounds)
      return context.makeImage()
    }
  }
}
