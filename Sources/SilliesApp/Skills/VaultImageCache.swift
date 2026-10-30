import AppKit
import Observation

/// Owns preview memory accounting and least-recently-used eviction.
@MainActor @Observable
final class VaultImageCache {
  nonisolated static let maximumBytes = 24 * 1024 * 1024
  private static let maximumImages = 16
  private static let bytesPerPixel = 4
  private var images: [String: NSImage] = [:]
  @ObservationIgnored private var costs: [String: Int] = [:]
  @ObservationIgnored private var order: [String] = []
  @ObservationIgnored private(set) var totalBytes = 0
  @ObservationIgnored var pinnedFilename: String?

  func image(named filename: String) -> NSImage? {
    guard let image = images[filename] else { return nil }
    if order.last != filename {
      order.removeAll { $0 == filename }
      order.append(filename)
    }
    return image
  }

  func store(_ image: CGImage, named filename: String) {
    let cost = max(
      image.bytesPerRow * image.height, image.width * image.height * Self.bytesPerPixel)
    remove(named: filename)
    guard cost <= Self.maximumBytes else { return }
    makeRoom(for: cost)
    images[filename] = NSImage(
      cgImage: image, size: NSSize(width: image.width, height: image.height))
    costs[filename] = cost
    totalBytes += cost
    order.append(filename)
  }

  private func makeRoom(for cost: Int) {
    while !order.isEmpty
      && (totalBytes + cost > Self.maximumBytes || order.count >= Self.maximumImages)
    {
      let index = order.firstIndex { $0 != pinnedFilename } ?? order.startIndex
      remove(named: order[index])
    }
  }

  func remove(named filename: String) {
    images.removeValue(forKey: filename)
    totalBytes -= costs.removeValue(forKey: filename) ?? 0
    order.removeAll { $0 == filename }
  }

  func removeAll() {
    images.removeAll()
    costs.removeAll()
    order.removeAll()
    totalBytes = 0
    pinnedFilename = nil
  }
}
