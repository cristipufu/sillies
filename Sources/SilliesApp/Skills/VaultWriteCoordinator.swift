import CoreGraphics
import Foundation
import SilliesCore
import SilliesPersistence

/// One active commit and one replaceable pending snapshot. Failed image payloads survive Retry.
@MainActor final class VaultWriteCoordinator {
  struct Image: Sendable {
    let id = UUID()
    let source: CGImage
    let encoded: Data?
  }
  struct Request: Sendable {
    let records: [SessionRecord]
    let images: [String: Image]
    let removals: Set<String>
  }
  typealias Commit = @Sendable (Request) throws -> Void
  private let queue: DispatchQueue
  private let commit: Commit
  private var pending: [SessionRecord]?
  private var images: [String: Image] = [:]
  private var removals: Set<String> = []
  private var writing = false
  private var scheduled = false
  private var failed = false
  private var waiters: [@MainActor @Sendable () -> Void] = []
  var report: (String?) -> Void = { _ in }
  private(set) var committedSnapshots = 0
  var pendingSnapshotCount: Int { (writing ? 1 : 0) + (pending == nil ? 0 : 1) }

  init(directory: URL, queue: DispatchQueue, commit: Commit? = nil) {
    self.queue = queue
    self.commit =
      commit ?? { request in
        let attachments = try request.images.map { filename, image in
          guard let data = image.encoded ?? VaultImageCodec.encodePNGData(from: image.source) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
          }
          return VaultCommitRepository.Attachment(filename: filename, data: data)
        }
        try VaultCommitRepository(directory: directory).commit(
          request.records, attachments: attachments, removing: request.removals)
      }
  }

  func stage(_ image: CGImage, encoded: Data?, filename: String) {
    images[filename] = Image(source: image, encoded: encoded)
  }

  func removeAttachment(_ filename: String) {
    images.removeValue(forKey: filename)
    removals.insert(filename)
  }

  func save(_ records: [SessionRecord]) {
    pending = records
    guard !writing, !scheduled, !failed else { return }
    scheduled = true
    MainRunLoopDelivery.perform { [weak self] in
      self?.scheduled = false
      self?.startNext()
    }
  }

  func retry() {
    failed = false
    startNext()
  }

  func flush(_ completion: @escaping @MainActor @Sendable () -> Void) {
    waiters.append(completion)
    startNext()
  }

  private func startNext() {
    guard !writing else { return }
    guard !failed, let records = pending else {
      finishWaiters()
      return
    }
    pending = nil
    writing = true
    let referenced = Set(records.compactMap(\.imageFilename))
    let request = Request(
      records: records, images: images.filter { referenced.contains($0.key) }, removals: removals)
    queue.async { [weak self, commit] in
      let result = Result { try commit(request) }
      MainRunLoopDelivery.perform { self?.complete(request, result: result) }
    }
  }

  private func complete(_ request: Request, result: Result<Void, Error>) {
    writing = false
    switch result {
    case .success:
      committedSnapshots += 1
      for (filename, image) in request.images where images[filename]?.id == image.id {
        images.removeValue(forKey: filename)
      }
      removals.subtract(request.removals)
      report(nil)
    case .failure(let error):
      failed = true
      if pending == nil { pending = request.records }
      let message = "Could not save the complete capture: \(error.localizedDescription)"
      fputs("\(message)\n", stderr)
      report(message)
    }
    startNext()
  }

  private func finishWaiters() {
    let waiting = waiters
    waiters.removeAll()
    for completion in waiting { completion() }
  }
}
