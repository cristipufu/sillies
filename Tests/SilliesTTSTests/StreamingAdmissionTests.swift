import Foundation
import SilliesInference
import Synchronization
import Testing

@Test func voicePreparationNeverPreemptsTextAndDefersWhenModelsCannotOverlap() async {
  let activity = InferenceActivity(overlapBudget: 1)
  let turn = UUID()
  let reservation = InferenceReservation(conversationID: turn, modelBytes: 1_024)
  let text = UUID()
  let cancelled = Mutex(false)
  #expect(
    await activity.claimText(
      text, reservation: reservation, cancel: { cancelled.withLock { $0 = true } }))
  #expect(await !activity.claimVoicePreparation(UUID(), reservation: reservation, cancel: {}))
  #expect(!cancelled.withLock { $0 })
  await activity.releaseText(text)
  let voice = UUID()
  #expect(await activity.claimVoicePreparation(voice, reservation: reservation, cancel: {}))
  await activity.releaseSynthesis(voice)
}

@Test func voicePreparationYieldsToNewInteractiveText() async throws {
  let activity = InferenceActivity()
  let voice = UUID()
  let cancelled = Mutex(false)
  #expect(
    await activity.claimVoicePreparation(
      voice, reservation: .init(conversationID: UUID(), modelBytes: 1),
      cancel: { cancelled.withLock { $0 = true } }))
  let text = Task { try await activity.waitForTextAdmission(.init(conversationID: UUID())) }
  for _ in 0..<100 {
    if cancelled.withLock({ $0 }) { break }
    try await Task.sleep(for: .milliseconds(2))
  }
  #expect(cancelled.withLock { $0 })
  await activity.releaseSynthesis(voice)
  try await text.value
}

@Test func voicePreparationSurvivesACompetingRequestWhileItsReplyIsStillGenerating() async {
  let activity = InferenceActivity()
  let text = UUID()
  let voice = UUID()
  let reservation = InferenceReservation(conversationID: UUID(), modelBytes: 1)
  let cancelled = Mutex(false)
  #expect(await activity.claimText(text, reservation: reservation, cancel: {}))
  #expect(
    await activity.claimVoicePreparation(
      voice, reservation: reservation, cancel: { cancelled.withLock { $0 = true } }))
  #expect(await !activity.claimText(UUID(), cancel: {}))
  #expect(!cancelled.withLock { $0 })
  await activity.releaseText(text)
  await activity.releaseSynthesis(voice)
}

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
