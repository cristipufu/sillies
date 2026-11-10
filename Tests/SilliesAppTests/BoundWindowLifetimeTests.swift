import ApplicationServices
import Foundation
import Synchronization
import Testing

@testable import SilliesApp

private final class BoundWindowInventoryProbe: Sendable {
  struct State {
    var identifiers: [pid_t] = [1]
    var isComplete = true
    var isApplicationHidden: Bool? = false
    var isAvailable = true
  }
  let state = Mutex(State())
  let frame = CGRect(x: 100, y: 100, width: 600, height: 400)
  var source: AccessibilityWindowSource.BoundWindows.Source {
    .init(
      inventory: { [self] _ in
        state.withLock { state in
          guard state.isAvailable else { return nil }
          return .init(
            windows: state.identifiers.map {
              .init(element: AXUIElementCreateApplication($0), frame: frame)
            },
            isComplete: state.isComplete, isApplicationHidden: state.isApplicationHidden)
        }
      })
  }
  func snapshot() -> [CGWindowID: WindowTargetSnapshot] {
    [42: .init(frame: frame, title: nil, visibility: .hidden, ownerPID: 123, isOnScreen: false)]
  }
}

@Test func boundWindowLifetimeClosesRetainedBackingWindowsByTheirVerifiedNativeIdentity() async {
  await Task.detached {
    let probe = BoundWindowInventoryProbe()
    let windows = AccessibilityWindowSource.BoundWindows(source: probe.source)
    #expect(windows.reconcile(probe.snapshot(), primaryScreenTop: 600)[42]?.visibility == .hidden)
    // Another window at identical bounds cannot substitute for the original AX identity.
    probe.state.withLock { $0.identifiers = [2] }
    let closed = windows.reconcile(probe.snapshot(), primaryScreenTop: 600)[42]
    #expect(closed?.visibility == .closed)
    #expect(closed?.closureEvidence == .accessibility)
    windows.clear()
    #expect(windows.reconcile(probe.snapshot(), primaryScreenTop: 600)[42]?.visibility == .hidden)
  }.value
}

@Test func boundWindowLifetimePreservesHiddenMinimizedAndUnavailableWindows() async {
  await Task.detached {
    let probe = BoundWindowInventoryProbe()
    let windows = AccessibilityWindowSource.BoundWindows(source: probe.source)
    let snapshots = probe.snapshot()
    _ = windows.reconcile(snapshots, primaryScreenTop: 600)
    _ = windows.reconcile(
      [42: .init(frame: .zero, title: nil, visibility: .unavailable)], primaryScreenTop: 600)
    // A minimized or hidden window remains a member even though it is ordered out.
    #expect(windows.reconcile(snapshots, primaryScreenTop: 600)[42]?.visibility == .hidden)
    probe.state.withLock {
      $0.isAvailable = false
      $0.identifiers = []
    }
    #expect(windows.reconcile(snapshots, primaryScreenTop: 600)[42]?.visibility == .hidden)
    probe.state.withLock {
      $0.isAvailable = true
      $0.isComplete = false
    }
    #expect(windows.reconcile(snapshots, primaryScreenTop: 600)[42]?.visibility == .hidden)
    probe.state.withLock {
      $0.isComplete = true
      $0.isApplicationHidden = true
    }
    #expect(windows.reconcile(snapshots, primaryScreenTop: 600)[42]?.visibility == .hidden)
    probe.state.withLock { $0.isApplicationHidden = nil }
    #expect(windows.reconcile(snapshots, primaryScreenTop: 600)[42]?.visibility == .hidden)
    probe.state.withLock { $0.isApplicationHidden = false }
    #expect(windows.reconcile(snapshots, primaryScreenTop: 600)[42]?.visibility == .closed)
  }.value
}

@Test func boundWindowLifetimeRejectsAmbiguousAnchorsAndDropsPreviousOwnership() async {
  await Task.detached {
    let probe = BoundWindowInventoryProbe()
    let windows = AccessibilityWindowSource.BoundWindows(source: probe.source)
    probe.state.withLock { $0.identifiers = [1, 2] }
    _ = windows.reconcile(probe.snapshot(), primaryScreenTop: 600)
    probe.state.withLock { $0.identifiers = [] }
    #expect(windows.reconcile(probe.snapshot(), primaryScreenTop: 600)[42]?.visibility == .hidden)
    probe.state.withLock { $0.identifiers = [1] }
    _ = windows.reconcile(probe.snapshot(), primaryScreenTop: 600)
    _ = windows.reconcile([:], primaryScreenTop: 600)
    probe.state.withLock { $0.identifiers = [] }
    #expect(windows.reconcile(probe.snapshot(), primaryScreenTop: 600)[42]?.visibility == .hidden)
  }.value
}
