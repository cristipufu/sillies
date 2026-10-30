import CoreGraphics
import Foundation
import SilliesCore
import Synchronization

/// Owns cached metadata and its synchronization. No AX or WindowServer call runs under the lock.
final class WindowTargetCache: Sendable {
  enum Lookup<Value: Sendable>: Sendable {
    case missing
    case cached(Value)
  }
  struct RoleRequest: Sendable {
    let snapshot: AccessibilityWindowRoleSnapshot?
    let refresh: UUID?
  }
  private struct Entry<Value: Sendable>: Sendable {
    let value: Value
    let capturedAt: TimeInterval
  }
  private struct State: Sendable {
    var roles: [pid_t: Entry<AccessibilityWindowRoleSnapshot?>] = [:]
    var pendingRoles: [pid_t: UUID] = [:]
    var candidates: [CGWindowID: Entry<WindowTargetCandidate?>] = [:]
  }
  private static let maximumRoles = 32
  private static let maximumCandidates = 128
  private static let roleLifetime: TimeInterval = 15
  private static let candidateLifetime: TimeInterval = 2
  private let state = Mutex(State())

  func storeRole(
    _ snapshot: AccessibilityWindowRoleSnapshot?, for pid: pid_t, at time: TimeInterval
  ) {
    guard pid > 0 else { return }
    state.withLock {
      $0.pendingRoles.removeValue(forKey: pid)
      Self.storeRole(snapshot, for: pid, at: time, in: &$0)
    }
  }

  func roleSnapshot(for pid: pid_t) -> AccessibilityWindowRoleSnapshot? {
    state.withLock { $0.roles[pid]?.value }
  }

  func requestRole(for pid: pid_t, at time: TimeInterval) -> RoleRequest {
    state.withLock {
      let entry = $0.roles[pid]
      let isFresh = entry.map { time - $0.capturedAt < Self.roleLifetime } ?? false
      guard pid > 0, !isFresh, $0.pendingRoles[pid] == nil else {
        return RoleRequest(snapshot: entry?.value, refresh: nil)
      }
      let generation = UUID()
      $0.pendingRoles[pid] = generation
      return RoleRequest(snapshot: entry?.value, refresh: generation)
    }
  }

  func finishRoleRefresh(
    _ snapshot: AccessibilityWindowRoleSnapshot?, for pid: pid_t,
    generation: UUID, at time: TimeInterval
  ) {
    state.withLock {
      guard $0.pendingRoles[pid] == generation else { return }
      $0.pendingRoles.removeValue(forKey: pid)
      Self.storeRole(snapshot, for: pid, at: time, in: &$0)
    }
  }

  private static func storeRole(
    _ snapshot: AccessibilityWindowRoleSnapshot?, for pid: pid_t,
    at time: TimeInterval, in state: inout State
  ) {
    // Preserve verified roles on timeout and back off before attempting another refresh.
    let retained = snapshot ?? state.roles[pid]?.value
    if state.roles.count >= maximumRoles { state.roles.removeAll(keepingCapacity: true) }
    state.roles[pid] = Entry(value: retained, capturedAt: time)
  }

  func storeCandidate(
    _ candidate: WindowTargetCandidate?, for id: CGWindowID, at time: TimeInterval
  ) {
    state.withLock {
      if $0.candidates.count >= Self.maximumCandidates {
        $0.candidates.removeAll(keepingCapacity: true)
      }
      $0.candidates[id] = Entry(value: candidate, capturedAt: time)
    }
  }

  func candidate(for id: CGWindowID, at time: TimeInterval) -> Lookup<WindowTargetCandidate?> {
    state.withLock {
      guard let entry = $0.candidates[id], time - entry.capturedAt < Self.candidateLifetime else {
        return .missing
      }
      return .cached(entry.value)
    }
  }

  func updateCandidateFrame(_ frame: CGRect, for id: CGWindowID) {
    state.withLock {
      guard let entry = $0.candidates[id], var candidate = entry.value else { return }
      candidate.frame = frame
      $0.candidates[id] = Entry(value: candidate, capturedAt: entry.capturedAt)
    }
  }
}
