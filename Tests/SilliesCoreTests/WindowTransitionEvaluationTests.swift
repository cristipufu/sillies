import Foundation
import Testing

@testable import SilliesCore

@Test func manipulationScopeCannotInheritQueuedApplicationDiscovery() {
  #expect(
    WindowRefreshScope.trackedWindow.merging(.applicationWindows, during: .manipulatingWindow)
      == .trackedWindow)
  #expect(
    WindowRefreshScope.applicationWindows.merging(.applicationWindows, during: .manipulatingWindow)
      == .trackedWindow)
  #expect(
    WindowRefreshScope.trackedWindow.merging(.applicationWindows, during: .idle)
      == .applicationWindows)
  #expect(WindowRefreshScope.trackedWindow.merging(nil, during: .idle) == .trackedWindow)
}

@Test func minimizeWaitsForOriginThenAcceptsStableReplacementUsingVirtualTime() throws {
  let origin = CGRect(x: 0, y: 0, width: 800, height: 600)
  let replacement = CGRect(x: 20, y: 40, width: 800, height: 600)
  let observation = WindowTransitionObservation(
    current: .init(id: 1, frame: origin), resolved: .init(id: 2, frame: replacement),
    visibility: .init(
      currentFrames: [1: origin, 2: replacement], priorFrames: [2: replacement],
      verifiedStandardFrames: [replacement]))
  let initiation = try #require(observation.initiation)
  #expect(initiation.reason == .minimize)
  var state = WindowTransitionState()
  state.begin(originWindowID: 1, reason: initiation.reason, at: 100)
  #expect(WindowTransitionEvaluation.shouldHold(&state, observation: observation, at: 100.2))
  #expect(!WindowTransitionEvaluation.shouldHold(&state, observation: observation, at: 100.61))
}

@Test func geometryTransitionSettlesAndCannotRemainHiddenIndefinitely() {
  let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
  let observation = WindowTransitionObservation(
    current: nil, resolved: .init(id: 1, frame: frame),
    visibility: .init(
      currentFrames: [1: frame], priorFrames: [1: frame], verifiedStandardFrames: [frame]))
  var state = WindowTransitionState()
  state.begin(originWindowID: 1, reason: .geometry, at: 100)
  #expect(WindowTransitionEvaluation.shouldHold(&state, observation: observation, at: 100.1))
  #expect(!WindowTransitionEvaluation.shouldHold(&state, observation: observation, at: 100.4))
  let missing = WindowTransitionObservation(
    current: nil, resolved: nil,
    visibility: .init(currentFrames: [:], priorFrames: [:], verifiedStandardFrames: nil))
  #expect(WindowTransitionEvaluation.shouldHold(&state, observation: missing, at: 100.5))
  #expect(!WindowTransitionEvaluation.shouldHold(&state, observation: missing, at: 101.21))
}
