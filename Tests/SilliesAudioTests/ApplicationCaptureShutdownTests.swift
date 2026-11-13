import Foundation
import SilliesCore
import Synchronization
import Testing

@testable import SilliesAudio

@Test func applicationCaptureScreenProviderJoinsStopsWhileStartupStillOwnsTheStream() {
  var lifetime = ScreenCaptureKitApplicationCapture.State()
  let started = lifetime.beginStartup()
  #expect(started)
  let completed = Mutex<[SessionFailure?]>([])
  for _ in 0..<2 {
    let action = lifetime.requestStop { outcome in completed.withLock { $0.append(outcome) } }
    guard case .wait = action else {
      Issue.record("Stop completed before startup drained")
      return
    }
  }
  #expect(completed.withLock { $0.isEmpty })
  let failure = SessionFailure(category: .finalization, message: "Fixture SDK stop failure")
  for callback in lifetime.finish(failure) { callback(failure) }
  #expect(completed.withLock { $0 } == [failure, failure])
  let lateCompletions = lifetime.finish(nil)
  #expect(lateCompletions.isEmpty)
  let action = lifetime.requestStop { _ in Issue.record("Cached stop must return its outcome") }
  guard case .completed(let outcome) = action else {
    Issue.record("Missing cached outcome")
    return
  }
  #expect(outcome == failure)
  let restarted = lifetime.beginStartup()
  #expect(!restarted)
}

@Test func applicationCaptureScreenProviderStoppedBeforeStartupNeverRequestsPermission() async {
  let provider = ScreenCaptureKitApplicationCapture(
    target: CoreAudioTestSystem.target,
    receive: { _ in Issue.record("Stopped provider delivered audio") }, failure: { _ in })
  #expect(await coreAudioStop(provider) == nil)
  #expect(await coreAudioStop(provider) == nil)
  do {
    try await provider.start()
    Issue.record("Stopped provider started")
  } catch { #expect(error is CancellationError) }
}
