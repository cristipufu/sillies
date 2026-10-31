import Foundation
import Synchronization

/// Shared by native notifications and metadata workers; no AppKit access is needed on a worker.
final class WindowTrackingExclusions: Sendable {
  static let shared = WindowTrackingExclusions()
  static let transparentOverlays = WindowTrackingExclusions()
  /// Only automated native-window fixtures opt in. Product windows are always excluded.
  static let nativeFixtures = WindowTrackingExclusions()
  private let windowIDs = Mutex<Set<UInt32>>([])

  func contains(_ id: UInt32) -> Bool { windowIDs.withLock { $0.contains(id) } }

  static func excludesSurface(_ id: UInt32, ownerPID: Int32) -> Bool {
    shared.contains(id)
      || (ownerPID == ProcessInfo.processInfo.processIdentifier && !nativeFixtures.contains(id))
  }

  func register(_ id: UInt32) -> Registration {
    _ = windowIDs.withLock { $0.insert(id) }
    return Registration(windowID: id, registry: self)
  }

  private func remove(_ id: UInt32) { _ = windowIDs.withLock { $0.remove(id) } }

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
