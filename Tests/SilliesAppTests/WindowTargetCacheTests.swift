import Foundation
import SilliesCore
import Testing

@testable import SilliesApp

@Test func roleCacheRejectsLateRefreshAndPreservesVerifiedSnapshotOnTimeout() throws {
  let cache = WindowTargetCache()
  let oldRefresh = try #require(cache.requestRole(for: 42, at: 0).refresh)
  #expect(cache.requestRole(for: 42, at: 1).refresh == nil)
  let verified = AccessibilityWindowRoleSnapshot(
    standardWindowFrames: [CGRect(x: 10, y: 20, width: 800, height: 600)],
    hasVerifiedWindowList: true)
  cache.storeRole(verified, for: 42, at: 2)
  cache.finishRoleRefresh(nil, for: 42, generation: oldRefresh, at: 3)
  #expect(cache.requestRole(for: 42, at: 4).snapshot == verified)
  let stale = cache.requestRole(for: 42, at: 20)
  #expect(stale.snapshot == verified)
  cache.finishRoleRefresh(nil, for: 42, generation: try #require(stale.refresh), at: 21)
  #expect(cache.requestRole(for: 42, at: 22).snapshot == verified)
  #expect(cache.requestRole(for: 42, at: 22).refresh == nil)
}

@Test func candidateCacheDistinguishesMissingFromRejectedAndDoesNotExtendFrameFreshness() {
  let cache = WindowTargetCache()
  cache.storeCandidate(nil, for: 1, at: 0)
  if case .cached(nil) = cache.candidate(for: 1, at: 1) {
  } else {
    Issue.record("Rejected window should be cached")
  }
  if case .missing = cache.candidate(for: 1, at: 3) {
  } else {
    Issue.record("Rejected result must expire")
  }
  let target = WindowTargetCandidate(
    windowID: 2, processID: 42, appName: "Test", bundleIdentifier: nil,
    windowTitle: nil, frame: CGRect(x: 0, y: 0, width: 800, height: 600))
  cache.storeCandidate(target, for: 2, at: 0)
  let moved = target.frame.offsetBy(dx: 20, dy: 10)
  cache.updateCandidateFrame(moved, for: 2)
  if case .cached(let cached) = cache.candidate(for: 2, at: 1) {
    #expect(cached?.frame == moved)
  } else {
    Issue.record("Expected updated candidate")
  }
  if case .missing = cache.candidate(for: 2, at: 3) {
  } else {
    Issue.record("Geometry update must not extend metadata lifetime")
  }
}

@Test func metadataCacheSupportsConcurrentReadersAndWriters() {
  let cache = WindowTargetCache()
  DispatchQueue.concurrentPerform(iterations: 200) { index in
    let id = UInt32(index % 16)
    cache.storeCandidate(nil, for: id, at: 0)
    _ = cache.candidate(for: id, at: 1)
    let pid = pid_t(id + 1)
    let request = cache.requestRole(for: pid, at: 1)
    if let generation = request.refresh {
      cache.finishRoleRefresh(nil, for: pid, generation: generation, at: 1)
    }
  }
  for id in UInt32(0)..<16 {
    if case .cached(nil) = cache.candidate(for: id, at: 1) {
    } else {
      Issue.record("Lost candidate entry")
    }
  }
}
