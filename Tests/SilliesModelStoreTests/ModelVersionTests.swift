import Foundation
import XCTest

@testable import SilliesModelStore

final class ModelVersionTests: XCTestCase, @unchecked Sendable {
  func testStagingDoesNotSwitchCurrentVersionAndActivationSurvivesRestart() async throws {
    let fixture = try ModelUpdateFixture()
    defer { fixture.cleanup() }
    let store = ModelStore(root: fixture.root, downloader: fixture.downloader)
    try await store.install(fixture.original) { _ in }
    try await store.stageUpdate(fixture.candidate, replacing: fixture.original) { _ in }
    let before = try await store.currentManifest(fixture.original)
    XCTAssertEqual(before, fixture.original)
    try await activate(fixture, store: store)
    let restarted = ModelStore(root: fixture.root, downloader: fixture.downloader)
    let current = try await restarted.currentManifest(fixture.original)
    let previous = try await restarted.previousManifest(fixture.original)
    XCTAssertEqual(current, fixture.candidate)
    XCTAssertEqual(previous, fixture.original)
    try await restarted.rollBack(fixture.original)
    let rolledBack = try await restarted.currentManifest(fixture.original)
    XCTAssertEqual(rolledBack, fixture.original)
    let originalAvailable = try await restarted.isInstalled(fixture.original)
    XCTAssertTrue(originalAvailable)
  }

  func testAnActiveSessionPreventsActivationAndRollback() async throws {
    let fixture = try ModelUpdateFixture()
    defer { fixture.cleanup() }
    let store = ModelStore(root: fixture.root, downloader: fixture.downloader)
    try await store.install(fixture.original) { _ in }
    try await store.stageUpdate(fixture.candidate, replacing: fixture.original) { _ in }
    let activeSession = try await store.acquire(fixture.original)
    let candidate = try await store.acquire(fixture.candidate)
    do {
      try await store.activate(
        fixture.candidate, replacing: fixture.original, validatedLease: candidate)
      XCTFail("Switched a model in use")
    } catch ModelStoreError.inUse {}
    do {
      try await store.rollBack(fixture.original)
      XCTFail("Rolled back a model in use")
    } catch ModelStoreError.inUse {}
    let current = try await store.currentManifest(fixture.original)
    XCTAssertEqual(current, fixture.original)
    withExtendedLifetime((activeSession, candidate)) {}
  }

  private func activate(_ fixture: ModelUpdateFixture, store: ModelStore) async throws {
    let lease = try await store.acquire(fixture.candidate)
    try await store.activate(fixture.candidate, replacing: fixture.original, validatedLease: lease)
  }
}
