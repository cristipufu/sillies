import Synchronization

/// Every finalizer joins the same release, including one already started by cancellation.
final class SpeechReservation: Sendable {
  private let completion = Mutex<Task<Void, Never>?>(nil)
  private let releaseResource: @Sendable () async -> Void

  init(release: @escaping @Sendable () async -> Void) {
    releaseResource = release
  }

  @discardableResult
  func release() -> Task<Void, Never> {
    completion.withLock { task in
      if let task { return task }
      let release = Task { [releaseResource] in await releaseResource() }
      task = release
      return release
    }
  }
}
