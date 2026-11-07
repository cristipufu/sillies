import Foundation
import SilliesCore
import SilliesVault

/// A durable, single-consumer queue. Closing a preview never loses the saved link.
@MainActor final class VaultLinkPreviewCoordinator {
  private let library: VaultLibrary
  private let fetcher: any VaultLinkPreviewFetching
  private var task: Task<Void, Never>?
  private var generation = UUID()
  private var enabled = true
  private var needsPump = false
  var changed: ((UUID) -> Void)?

  init(
    library: VaultLibrary, fetcher: any VaultLinkPreviewFetching
  ) {
    self.library = library
    self.fetcher = fetcher
  }

  func pump() {
    guard enabled else { return }
    needsPump = true
    guard task == nil else { return }
    needsPump = false
    let token = UUID()
    generation = token
    task = Task { [weak self] in await self?.process(token) }
  }
  func resume() {
    enabled = true
    pump()
  }
  func stop() {
    enabled = false
    generation = UUID()
    task?.cancel()
    needsPump = false
  }

  private func process(_ token: UUID) async {
    defer {
      task = nil
      if enabled, needsPump { pump() }
    }
    do {
      while enabled, generation == token {
        try Task.checkCancellation()
        guard let header = try await library.pendingLink(), let link = header.metadata.link else {
          return
        }
        let preview: VaultLinkPreview
        do { preview = try await fetcher.fetch(link) } catch is CancellationError {
          throw CancellationError()
        } catch {
          var unavailable = link
          unavailable.previewState = .unavailable
          preview = .init(link: unavailable)
          fputs("Vault link preview unavailable: \(String(describing: type(of: error)))\n", stderr)
        }
        try Task.checkCancellation()
        guard generation == token else { return }
        let saved = try await library.saveLinkPreview(preview, id: header.id)
        guard enabled, generation == token, !Task.isCancelled else { return }
        if saved != nil { changed?(header.id) }
        await Task.yield()
      }
    } catch is CancellationError { return } catch {
      fputs("Vault link preview queue failed: \(error)\n", stderr)
    }
  }
  isolated deinit { stop() }
}
