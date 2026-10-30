import AppKit

/// A delayed image copy cannot replace a newer copy request or another application's clipboard.
@MainActor
final class VaultClipboard {
  private let pasteboard: NSPasteboard
  private let queue: DispatchQueue
  private var generation: UInt64 = 0

  init(pasteboard: NSPasteboard, queue: DispatchQueue) {
    self.pasteboard = pasteboard
    self.queue = queue
  }

  func copyText(_ text: String) {
    guard !text.isEmpty else { return }
    generation &+= 1
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
  }

  func copyImage(at url: URL?, fallback: CGImage?) {
    generation &+= 1
    let request = generation
    let changeCount = pasteboard.changeCount
    queue.async { [weak self] in
      let data = url.flatMap(Self.readImage) ?? fallback.flatMap(VaultImageCodec.encodePNGData)
      guard let data else { return }
      MainRunLoopDelivery.perform { [weak self] in
        self?.publish(data, request: request, changeCount: changeCount)
      }
    }
  }

  private func publish(_ data: Data, request: UInt64, changeCount: Int) {
    guard request == generation, pasteboard.changeCount == changeCount else { return }
    pasteboard.clearContents()
    pasteboard.setData(data, forType: .png)
  }

  nonisolated private static func readImage(at url: URL) -> Data? {
    dispatchPrecondition(condition: .notOnQueue(.main))
    do {
      return try Data(contentsOf: url)
    } catch {
      fputs("Vault image read failed: \(error.localizedDescription)\n", stderr)
      return nil
    }
  }
}
