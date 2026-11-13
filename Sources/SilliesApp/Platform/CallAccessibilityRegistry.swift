import Foundation

/// App-owned leases keep one recording from disabling accessibility used by another recording.
actor CallAccessibilityRegistry {
  struct Restoration {
    let restore: () -> Bool
  }
  struct Lease: Sendable, Hashable {
    let processID: Int32
    let id: UUID
  }
  private struct Application {
    var leases: Set<UUID>
    let restoration: Restoration
  }
  private let prepare: @Sendable (Int32) -> Restoration
  private var applications: [Int32: Application] = [:]
  init(prepare: @escaping @Sendable (Int32) -> Restoration) { self.prepare = prepare }
  func acquire(processID: Int32) -> Lease {
    let lease = Lease(processID: processID, id: UUID())
    if var application = applications[processID] {
      application.leases.insert(lease.id)
      applications[processID] = application
    } else {
      applications[processID] = .init(leases: [lease.id], restoration: prepare(processID))
    }
    return lease
  }
  func release(_ lease: Lease) {
    guard var application = applications[lease.processID],
      application.leases.remove(lease.id) != nil
    else { return }
    guard application.leases.isEmpty else {
      applications[lease.processID] = application
      return
    }
    applications[lease.processID] = nil
    if !application.restoration.restore() {
      fputs("Call-speaker accessibility restoration failed.\n", stderr)
    }
  }
}
