import Foundation
import Synchronization
import XCTest

@testable import SilliesModelStore

final class ModelUpdateCheckerTests: XCTestCase, @unchecked Sendable {
  func testDailySchedulePersistsAcrossRestartAndManualChecksBypassIt() async throws {
    let fixture = try ModelUpdateFixture()
    defer { fixture.cleanup() }
    let store = ModelStore(root: fixture.root, downloader: fixture.downloader)
    try await store.install(fixture.original) { _ in }
    let clock = Mutex(Date(timeIntervalSince1970: 1_000_000))
    let discovery = DiscoveryProbe(candidate: fixture.candidate)
    let location = fixture.root.appendingPathComponent("updates.json")
    let checker = ModelUpdateChecker(
      store: store, location: location, discovery: discovery, now: { clock.withLock { $0 } })
    let first = try await checker.check(.scheduled, models: [fixture.original])
    XCTAssertEqual(first.entries[fixture.original.model.id]?.candidate, fixture.candidate)
    let restarted = ModelUpdateChecker(
      store: store, location: location, discovery: discovery, now: { clock.withLock { $0 } })
    _ = try await restarted.check(.scheduled, models: [fixture.original])
    let beforeDay = await discovery.calls
    XCTAssertEqual(beforeDay, 1)
    clock.withLock { $0 += ModelUpdateChecker.checkInterval }
    _ = try await restarted.check(.scheduled, models: [fixture.original])
    _ = try await restarted.check(.manual, models: [fixture.original])
    let calls = await discovery.calls
    XCTAssertEqual(calls, 3)
  }

  func testOfflineCheckPreservesCandidateAndNeverChangesInstalledModel() async throws {
    let fixture = try ModelUpdateFixture()
    defer { fixture.cleanup() }
    let store = ModelStore(root: fixture.root, downloader: fixture.downloader)
    try await store.install(fixture.original) { _ in }
    let discovery = DiscoveryProbe(candidate: fixture.candidate)
    let checker = ModelUpdateChecker(
      store: store, location: fixture.root.appendingPathComponent("updates.json"),
      discovery: discovery)
    let first = try await checker.check(.manual, models: [fixture.original])
    await discovery.goOffline()
    let offline = try await checker.check(.manual, models: [fixture.original])
    XCTAssertEqual(offline.entries[fixture.original.model.id]?.candidate, fixture.candidate)
    XCTAssertNotNil(offline.entries[fixture.original.model.id]?.notice)
    XCTAssertEqual(offline.checkedAt, first.checkedAt)
    let current = try await store.currentManifest(fixture.original)
    XCTAssertEqual(current, fixture.original)
  }

  func testAbsentModelsAreNotQueried() async throws {
    let fixture = try ModelUpdateFixture()
    defer { fixture.cleanup() }
    let discovery = DiscoveryProbe(candidate: fixture.candidate)
    let checker = ModelUpdateChecker(
      store: ModelStore(root: fixture.root),
      location: fixture.root.appendingPathComponent("updates.json"), discovery: discovery)
    let result = try await checker.check(.manual, models: [fixture.original])
    let calls = await discovery.calls
    XCTAssertEqual(calls, 0)
    XCTAssertTrue(result.entries.isEmpty)
  }
}

private actor DiscoveryProbe: ModelUpdateDiscovering {
  let update: SpeechModelManifest
  private(set) var calls = 0
  private var isOffline = false
  init(candidate: SpeechModelManifest) { update = candidate }
  func goOffline() { isOffline = true }
  func candidate(for installed: SpeechModelManifest) async throws -> SpeechModelManifest? {
    calls += 1
    if isOffline { throw URLError(.notConnectedToInternet) }
    return update
  }
}
