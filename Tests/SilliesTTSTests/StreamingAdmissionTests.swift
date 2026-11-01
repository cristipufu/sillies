import Foundation
import SilliesInference
import Synchronization
import Testing

@Test func sameTurnTextAndVoiceOverlapWithoutCancellingEitherBranch() async {
  let activity = InferenceActivity(overlapBudget: 8 * 1_024 * 1_024 * 1_024)
  let group = UUID()
  let textID = UUID()
  let voiceID = UUID()
  let cancelled = Mutex(false)
  let reservation = InferenceReservation(conversationID: group, modelBytes: 1_024)
  #expect(
    await activity.claimText(
      textID, reservation: reservation, cancel: { cancelled.withLock { $0 = true } }))
  #expect(await activity.claimSynthesis(voiceID, reservation: reservation, cancel: {}))
  #expect(!cancelled.withLock { $0 })
  #expect(await !activity.requiresTextEviction(textID))
  await activity.releaseSynthesis(voiceID)
  await activity.releaseText(textID)
}

@Test func oversizedVoiceWaitsForTextCompletionWithoutDiscardingItsOutput() async throws {
  let activity = InferenceActivity(overlapBudget: 1)
  let group = UUID()
  let textID = UUID()
  let voiceID = UUID()
  let cancelled = Mutex(false)
  let admitted = Mutex(false)
  let reservation = InferenceReservation(conversationID: group, modelBytes: 1_024)
  #expect(
    await activity.claimText(
      textID, reservation: reservation, cancel: { cancelled.withLock { $0 = true } }))
  let voice = Task {
    let result = await activity.claimSynthesis(voiceID, reservation: reservation, cancel: {})
    admitted.withLock { $0 = result }
    return result
  }
  for _ in 0..<100 {
    if await activity.requiresTextEviction(textID) { break }
    try await Task.sleep(for: .milliseconds(1))
  }
  #expect(await activity.requiresTextEviction(textID))
  #expect(!cancelled.withLock { $0 })
  #expect(!admitted.withLock { $0 })
  await activity.releaseText(textID)
  #expect(await voice.value)
  await activity.releaseSynthesis(voiceID)
}

@Test func cancelledVoiceAdmissionDoesNotLeaveASchedulerReservation() async throws {
  let activity = InferenceActivity(overlapBudget: 1)
  let group = UUID()
  let textID = UUID()
  let voiceID = UUID()
  let reservation = InferenceReservation(conversationID: group, modelBytes: 1_024)
  #expect(await activity.claimText(textID, reservation: reservation, cancel: {}))
  let voice = Task { await activity.claimSynthesis(voiceID, reservation: reservation, cancel: {}) }
  for _ in 0..<100 {
    if await activity.requiresTextEviction(textID) { break }
    try await Task.sleep(for: .milliseconds(1))
  }
  voice.cancel()
  #expect(await !voice.value)
  await activity.releaseText(textID)
  let next = UUID()
  #expect(await activity.claimSynthesis(next, cancel: {}))
  await activity.releaseSynthesis(next)
}

@Test func cachedModelsAreEvictedBeforeLoadingAnIncompatiblePeer() async {
  let activity = InferenceActivity(overlapBudget: 1)
  let evictions = Mutex(0)
  let resident = UUID()
  let reservation = InferenceReservation(modelBytes: 1_024)
  await activity.rememberTextModel(id: resident, reservation: reservation) {
    evictions.withLock { $0 += 1 }
    await activity.forgetTextModel(resident)
  }
  await activity.prepareVoiceModel(reservation)
  await activity.prepareVoiceModel(reservation)
  #expect(evictions.withLock { $0 } == 1)
}
