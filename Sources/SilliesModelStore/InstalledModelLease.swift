import Foundation

package final class InstalledModelLease: Sendable {
  package let directory: URL
  let token: UUID
  private let release: @Sendable () async -> Void
  init(directory: URL, token: UUID, release: @escaping @Sendable () async -> Void) {
    self.directory = directory
    self.token = token
    self.release = release
  }
  package func close() async { await release() }
  deinit {
    let release = release
    Task { await release() }
  }
}
