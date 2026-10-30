import Foundation

/// Evaluates visibility using supplied snapshots and monotonic time; performs no I/O.
public enum WindowTransitionEvaluation {
  private static let settleInterval: Double = 0.22
  private static let minimumHideDuration: Double = 0.18
  private static let maxMinimizeDuration: Double = 0.60
  private static let maxTransitionDuration: Double = 1.20

  public static func shouldHold(
    _ state: inout WindowTransitionState, observation: WindowTransitionObservation, at now: Double
  ) -> Bool {
    guard now - state.startedAt < maxTransitionDuration else { return false }
    recordOriginActivity(&state, observation: observation, at: now)
    guard let candidate = observation.resolved else {
      return holdMissingCandidate(&state, visibility: observation.visibility, at: now)
    }
    if isAwaitingMinimizedOrigin(state, observation: observation, at: now) {
      if candidate.id != state.originWindowID {
        state.observeCandidate(windowID: candidate.id, frame: candidate.frame, at: now)
      }
      return true
    }
    if let priorFrame = observation.visibility.priorFrames[Int(candidate.id)],
      !WindowFrameComparison.matches(priorFrame, candidate.frame)
    {
      state.recordActivity(at: now)
      state.observeCandidate(windowID: candidate.id, frame: candidate.frame, at: now)
      return true
    }
    return !isCandidateSettled(&state, observation: observation, at: now)
  }

  private static func recordOriginActivity(
    _ state: inout WindowTransitionState, observation: WindowTransitionObservation, at now: Double
  ) {
    guard let originID = state.originWindowID,
      let current = observation.visibility.currentFrames[Int(originID)],
      let prior = observation.visibility.priorFrames[Int(originID)],
      !WindowFrameComparison.matches(prior, current),
      observation.resolved?.id == nil || observation.resolved?.id == originID
    else { return }
    state.recordActivity(at: now)
  }

  private static func holdMissingCandidate(
    _ state: inout WindowTransitionState, visibility: WindowTransitionObservation.Visibility,
    at now: Double
  ) -> Bool {
    if let originID = state.originWindowID,
      visibility.currentFrames[Int(originID)] == nil,
      visibility.verifiedStandardFrames?.isEmpty == true,
      now - state.lastActivityAt >= settleInterval
    {
      return false
    }
    state.clearCandidate(at: now)
    return true
  }

  private static func isAwaitingMinimizedOrigin(
    _ state: WindowTransitionState, observation: WindowTransitionObservation, at now: Double
  ) -> Bool {
    guard state.isMinimizingOrigin, now - state.startedAt < maxMinimizeDuration else {
      return false
    }
    if observation.resolved?.id == state.originWindowID { return true }
    guard let originID = state.originWindowID else { return false }
    return observation.visibility.currentFrames[Int(originID)] != nil
  }

  private static func isCandidateSettled(
    _ state: inout WindowTransitionState, observation: WindowTransitionObservation, at now: Double
  ) -> Bool {
    guard let candidate = observation.resolved else { return false }
    let matchesCandidate =
      state.candidateWindowID == candidate.id
      && state.candidateFrame.map { WindowFrameComparison.matches($0, candidate.frame) } == true
    let matchesPrior =
      observation.visibility.priorFrames[Int(candidate.id)]
      .map { WindowFrameComparison.matches($0, candidate.frame) } ?? false
    state.observeCandidate(windowID: candidate.id, frame: candidate.frame, at: now)
    guard now - state.startedAt >= minimumHideDuration else { return false }
    if state.isMinimizingOrigin, candidate.id != state.originWindowID, matchesPrior { return true }
    return matchesCandidate && now - state.candidateStableSince >= settleInterval
      && now - state.lastActivityAt >= settleInterval
  }
}
