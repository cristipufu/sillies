import ApplicationServices
import CoreGraphics
import Foundation
import SilliesCore
import Synchronization

extension AccessibilityWindowSource {
  /// Used only by the metadata worker, on the existing skill clock. No observers or timers.
  final class BoundWindows: Sendable {
    struct Inventory {
      struct Window {
        let element: AXUIElement
        let frame: CGRect
      }
      let windows: [Window]
      let isComplete: Bool
      let isApplicationHidden: Bool?
    }
    struct Source: Sendable {
      let inventory: @Sendable (pid_t) -> Inventory?
      static let native = Source(inventory: boundWindowInventory)
    }
    private struct Anchor {
      let processID: pid_t
      let element: AXUIElement
      private var lifetime = BoundWindowLifetime()

      init(processID: pid_t, element: AXUIElement) {
        self.processID = processID
        self.element = element
        lifetime.observe(.present)
      }

      mutating func observe(_ inventory: Inventory) -> BoundWindowLifetime.State {
        if inventory.windows.contains(where: { CFEqual($0.element, element) }) {
          lifetime.observe(.present)
        } else if inventory.isComplete, inventory.isApplicationHidden == false {
          lifetime.observe(.absent)
        } else {
          lifetime.observe(.unavailable)
        }
        return lifetime.state
      }
    }
    // SDK elements never escape this mutex or the off-main metadata worker.
    private let anchors = Mutex<[CGWindowID: Anchor]>([:])
    private let source: Source

    init(source: Source = .native) { self.source = source }

    func reconcile(
      _ snapshots: [CGWindowID: WindowTargetSnapshot], primaryScreenTop: Double
    ) -> [CGWindowID: WindowTargetSnapshot] {
      dispatchPrecondition(condition: .notOnQueue(.main))
      return anchors.withLock { anchors in
        anchors = anchors.filter { id, anchor in
          guard let snapshot = snapshots[id], snapshot.visibility != .closed else { return false }
          return snapshot.ownerPID.map { $0 == anchor.processID } ?? true
        }
        var inventories: [pid_t: Inventory] = [:]
        var attempted: Set<pid_t> = []
        var result = snapshots
        for (id, snapshot) in snapshots {
          guard let pid = snapshot.ownerPID, pid > 0,
            snapshot.visibility != .closed, snapshot.visibility != .unavailable
          else { continue }
          // Covered windows are still on screen. Once anchored they need no AX polling.
          if anchors[id] != nil, snapshot.isOnScreen { continue }
          if attempted.insert(pid).inserted, let inventory = source.inventory(pid) {
            inventories[pid] = inventory
          }
          guard let inventory = inventories[pid] else { continue }
          if anchors[id] == nil {
            anchors[id] = makeAnchor(
              for: snapshot, in: inventory, primaryScreenTop: primaryScreenTop)
          }
          guard var anchor = anchors[id] else { continue }
          let lifetime = anchor.observe(inventory)
          anchors[id] = anchor
          if lifetime == .closed {
            var closed = snapshot
            closed.visibility = .closed
            closed.closureEvidence = .accessibility
            result[id] = closed
          }
        }
        return result
      }
    }

    private func makeAnchor(
      for snapshot: WindowTargetSnapshot, in inventory: Inventory, primaryScreenTop: Double
    ) -> Anchor? {
      guard inventory.isComplete, let pid = snapshot.ownerPID else { return nil }
      let matches = inventory.windows.filter { window in
        let converted = ScreenCoordinates.appKitRect(
          fromAccessibility: window.frame, primaryScreenTop: primaryScreenTop)
        return WindowFrameComparison.matches(converted, snapshot.frame)
      }
      // Ambiguous backing windows cannot establish an identity.
      guard matches.count == 1, let window = matches.first else { return nil }
      return Anchor(processID: pid, element: window.element)
    }

    func clear() {
      dispatchPrecondition(condition: .notOnQueue(.main))
      anchors.withLock { $0.removeAll() }
    }
  }

}
