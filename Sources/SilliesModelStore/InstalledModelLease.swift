import Foundation

package final class InstalledModelLease: Sendable {
  package let directory: URL
  let token: UUID
  private let release: @Sendable () -> Void
  init(directory: URL, token: UUID, release: @escaping @Sendable () -> Void) {
    self.directory = directory
    self.token = token
    self.release = release
  }
  deinit { release() }
}
