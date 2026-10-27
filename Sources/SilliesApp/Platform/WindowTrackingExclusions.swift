import Foundation

/// Shared by native notifications and metadata workers; no AppKit access is needed on a worker.
final class WindowTrackingExclusions: @unchecked Sendable {
  static let shared = WindowTrackingExclusions()
  static let transparentOverlays = WindowTrackingExclusions()
  private let lock = NSLock()
  private var windowIDs: Set<UInt32> = []

  func contains(_ id: UInt32) -> Bool { lock.withLock { windowIDs.contains(id) } }

  func register(_ id: UInt32) -> Registration {
    _ = lock.withLock { windowIDs.insert(id) }
    return Registration(windowID: id, registry: self)
  }

  private func remove(_ id: UInt32) { _ = lock.withLock { windowIDs.remove(id) } }

  final class Registration: Sendable {
    let windowID: UInt32
    private let registry: WindowTrackingExclusions
    fileprivate init(windowID: UInt32, registry: WindowTrackingExclusions) {
      self.windowID = windowID
      self.registry = registry
    }
    deinit { registry.remove(windowID) }
  }
}
