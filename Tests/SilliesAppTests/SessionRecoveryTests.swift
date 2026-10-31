import Foundation
import SilliesAudio
import SilliesCore
import SilliesPersistence
import SilliesReasoning
import SilliesSpeech
import Testing

@testable import SilliesApp

@Test func sessionRecoveryTargetsTheDeniedPermission() {
  #expect(
    SessionRecovery.settingsURL(for: .openMicrophoneSettings)?.absoluteString
      == "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
  #expect(
    SessionRecovery.settingsURL(for: .openScreenRecordingSettings)?.absoluteString
      == "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
}

@Test(arguments: [
  SessionFailure.RecoveryAction.openMicrophoneSettings, .openScreenRecordingSettings,
])
@MainActor func permissionFailureSurvivesLivePresentationAndVaultSave(
  _ recovery: SessionFailure.RecoveryAction
) async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let failure = SessionFailure.permissionDenied(recovery)
  let vault = SessionVaultStore(
    directory: directory,
    notesGenerator: { _ in LocalNotes(summary: "Discuss system settings tomorrow.", actions: []) })
  let coordinator = SkillCoordinator(
    vault: vault,
    audioFactory: { _, update in FailedAudioCapture(failure: failure, update: update) },
    audioLanguages: fixtureAudioLanguages())
  let (failures, observed) = AsyncStream<SessionFailure>.makeStream()
  coordinator.onBindingChanged = { _, _ in
    if case .failed(let failure) = coordinator.activeAudioSession?.phase { observed.yield(failure) }
  }
  defer {
    coordinator.onBindingChanged = nil
    observed.finish()
  }
  coordinator.startSkill(.record, for: "mochi", companionName: "Mochi")
  var iterator = failures.makeAsyncIterator()
  #expect(await iterator.next() == failure)
  #expect(coordinator.activeAudioSession?.canFinish == true)
  await coordinator.shutdown()
  let id = try #require(vault.records.first?.id)
  let saved = try #require(try await vault.record(id: id))
  #expect(saved.failure == failure)
  #expect(saved.transcript == "Preserved words before interruption.")
  #expect(saved.requiresPermissionAccess)
}

private final class FailedAudioCapture: SessionAudioCapture {
  private let failure: SessionFailure
  private let update: @Sendable (AudioCaptureUpdate) -> Void

  init(failure: SessionFailure, update: @escaping @Sendable (AudioCaptureUpdate) -> Void) {
    self.failure = failure
    self.update = update
  }
  func start() { update(.failed(failure)) }
  func pause() {}
  func resume() {}
  func changeLanguage(_ language: SpeechLanguage) {}
  func finish(completion: @escaping @Sendable (AudioCaptureResult) -> Void) {
    completion(
      AudioCaptureResult(
        transcript: "Preserved words before interruption.", recordingURL: nil, duration: 10,
        failure: failure))
  }
}
