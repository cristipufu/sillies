import AppKit
import SilliesCore
import SilliesPersistence

/// Native previews and clipboard ownership stay outside the Vault application module.
@MainActor final class VaultMediaStore {
  enum ImageState {
    case loading
    case available(NSImage)
    case unavailable
  }
  private let cache = VaultImageCache()
  private let staged = VaultPreviewBuffer()
  private var pending: Set<String> = []
  private var removed: Set<String> = []
  private let files: VaultFileStorage
  private let queue: DispatchQueue
  private let clipboard: VaultClipboard
  var cachedBytes: Int { cache.totalBytes }

  init(directory: URL, pasteboard: NSPasteboard, queue: DispatchQueue) {
    files = VaultFileStorage(directory: directory)
    self.queue = queue
    clipboard = VaultClipboard(pasteboard: pasteboard, queue: queue)
  }
  func url(_ filename: String?) -> URL? {
    guard let filename else { return nil }
    do { return try files.attachmentURL(for: filename) } catch {
      fputs("Vault rejected attachment filename: \(error)\n", stderr)
      return nil
    }
  }
  func stage(_ image: CGImage, filename: String) {
    removed.remove(filename)
    if max(image.width, image.height) <= VaultImageCodec.maxPreviewPixelDimension {
      cache.store(image, named: filename)
      return
    }
    pending.insert(filename)
    queue.async { [weak self, staged] in
      staged.append(filename: filename, image: VaultImageCodec.preparePreview(from: image))
      MainRunLoopDelivery.perform { self?.drain() }
    }
  }
  func image(_ filename: String?) -> NSImage? {
    drain()
    return filename.flatMap { cache.image(named: $0) }
  }
  func imageState(_ filename: String?) -> ImageState {
    if let image = image(filename) { return .available(image) }
    guard let filename, url(filename) != nil, !cache.isUnavailable(filename) else {
      return .unavailable
    }
    return .loading
  }
  func prepare(_ filename: String?) {
    guard let filename, !pending.contains(filename), cache.image(named: filename) == nil,
      let url = url(filename)
    else { return }
    cache.remove(named: filename)
    removed.remove(filename)
    pending.insert(filename)
    queue.async { [weak self, staged] in
      let image = VaultImageCodec.decodePreview(at: url)
      if let image {
        staged.append(filename: filename, image: image)
      }
      MainRunLoopDelivery.perform {
        self?.pending.remove(filename)
        self?.drain()
        if image == nil, let self, self.removed.remove(filename) == nil {
          self.cache.recordFailure(named: filename)
        }
      }
    }
  }
  func pin(_ filename: String?) {
    cache.pinnedFilename = filename
    prepare(filename)
  }
  func remove(_ filename: String?) {
    guard let filename else { return }
    if pending.contains(filename) { removed.insert(filename) }
    cache.remove(named: filename)
    staged.remove(filename: filename)
  }
  func clear() {
    removed.formUnion(pending)
    cache.removeAll()
    staged.removeAll()
  }
  func drain() {
    for entry in staged.drain() {
      pending.remove(entry.filename)
      guard removed.remove(entry.filename) == nil else { continue }
      cache.store(entry.image, named: entry.filename)
    }
  }
  func copyText(_ text: String) { clipboard.copyText(text) }
  func copyImage(_ filename: String?) {
    let fallback = image(filename)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    clipboard.copyImage(at: url(filename), fallback: fallback)
  }
}
