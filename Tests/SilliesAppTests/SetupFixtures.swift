import Foundation
import SilliesAudio
import SilliesChat
import SilliesCore
import SilliesReasoning
import SilliesSpeech
import SilliesTTS
import Synchronization
import Testing

@testable import SilliesApp

final class SetupPermissionProbe: Sendable {
  let granted = Mutex(true)
}

actor SetupReplyProbe: ConversationResponding {
  var notice: String?
  private var waiting: CheckedContinuation<Void, Never>?
  private var holdsNext = false
  private(set) var checks = 0
  init(notice: String? = nil) { self.notice = notice }
  func setNotice(_ notice: String?) { self.notice = notice }
  func holdNextCheck() { holdsNext = true }
  func releaseCheck() {
    waiting?.resume()
    waiting = nil
  }
  func availabilityNotice(localeIdentifier: String?) async -> String? {
    checks += 1
    if holdsNext {
      holdsNext = false
      await withCheckedContinuation { waiting = $0 }
    }
    return notice
  }
  func reply(to context: ChatContext, progress: @escaping @Sendable (ChatProgress) -> Void)
    async throws -> ChatReply
  { .init(text: "Fixture reply") }
}

actor SetupVoiceProbe: ChatSpeechOutput {
  var notice: String?
  private var holdsStop = false
  private var cancelsNextSpeech = false
  private var pendingStop: CheckedContinuation<Void, Never>?
  private var holdsSpeech = false
  private var pendingSpeech: CheckedContinuation<Void, Never>?
  private var playback: (@Sendable (SpeechPlaybackUpdate) -> Void)?
  private(set) var starts = 0
  init(notice: String? = nil) { self.notice = notice }
  func setNotice(_ notice: String?) { self.notice = notice }
  func holdStop() { holdsStop = true }
  func cancelNextSpeech() { cancelsNextSpeech = true }
  func holdSpeech() { holdsSpeech = true }
  func emitPlayback(_ update: SpeechPlaybackUpdate) { playback?(update) }
  private func releaseSpeech() {
    holdsSpeech = false
    pendingSpeech?.resume()
    pendingSpeech = nil
  }
  func releaseStop() {
    holdsStop = false
    pendingStop?.resume()
    pendingStop = nil
  }
  var isStopping: Bool { pendingStop != nil }
  func availabilityNotice(language: String) async -> String? { notice }
  func speak(
    _ request: ChatSpeechRequest, receive: @escaping @Sendable (SpeechPlaybackUpdate) -> Void
  ) async throws -> String? {
    starts += 1
    playback = receive
    if cancelsNextSpeech {
      cancelsNextSpeech = false
      throw CancellationError()
    }
    if holdsSpeech { await withCheckedContinuation { pendingSpeech = $0 } }
    return notice
  }
  func stop(id: UUID) async {
    releaseSpeech()
    if holdsStop { await withCheckedContinuation { pendingStop = $0 } }
  }
  func pause(id: UUID) async {}
  func resume(id: UUID) async {}
}

final class SetupCaptureProbe: ConversationCapture, Sendable {
  let starts = Mutex(0)
  let finishes = Mutex(0)
  let held = Mutex(false)
  let completion = Mutex<(@Sendable (AudioCaptureResult) -> Void)?>(nil)
  func start() { starts.withLock { $0 += 1 } }
  func finishTurn(completion: @escaping @Sendable (AudioCaptureResult) -> Void) {
    finish(completion: completion)
  }
  func finish(completion: @escaping @Sendable (AudioCaptureResult) -> Void) {
    finishes.withLock { $0 += 1 }
    if held.withLock({ $0 }) {
      self.completion.withLock { $0 = completion }
    } else {
      completion(.init(transcript: "Test words", recordingURL: nil, duration: 1, failure: nil))
    }
  }
  func release() {
    let callback = completion.withLock { callback in
      defer { callback = nil }
      return callback
    }
    callback?(.init(transcript: "Test words", recordingURL: nil, duration: 1, failure: nil))
  }
}

@MainActor final class SetupFixture {
  let domain = "sillies-setup-\(UUID().uuidString)"
  let defaults: UserDefaults
  let characters: [CharacterDefinition]
  let preferences: CompanionPreferences
  let journey: SetupJourney
  let reply: SetupReplyProbe
  let voice: SetupVoiceProbe
  let capture = SetupCaptureProbe()
  let permissions = SetupPermissionProbe()
  var launches: [(String, SetupActivity)] = []
  var destinations: [SettingsDestination] = []
  var busy = false
  var launchFailure: SessionFailure?
  var meetingLanguage: String? = "en"

  init(reply: SetupReplyProbe = .init(), voice: SetupVoiceProbe = .init()) throws {
    defaults = try #require(UserDefaults(suiteName: domain))
    characters = try CharacterCatalog().characters
    preferences = CompanionPreferences(defaults: defaults, characters: characters)
    journey = SetupJourney(defaults: defaults, availableIDs: characters.map(\.id))
    self.reply = reply
    self.voice = voice
  }

  var services: ChatServices {
    .init(
      captureFactory: { [capture] _, _ in capture },
      loadLanguages: { .init(languages: [.init(id: "en", name: "English", isInstalled: true)]) },
      conversation: reply, speech: voice, deliver: { MainRunLoopDelivery.perform($0) },
      history: .transient)
  }
  func makePresentation() -> SetupPresentation {
    SetupPresentation(
      journey: journey, profiles: preferences, characters: characters,
      audio: SetupAudioPreview(isBusy: { [weak self] in self?.busy == true }),
      actions: .init(
        services: { [unowned self] _ in self.services },
        isGranted: { [permissions] permission in
          permission != .openMicrophoneSettings || permissions.granted.withLock { $0 }
        },
        requestPermission: { [permissions] _ in permissions.granted.withLock { $0 = true } },
        meetingLanguage: { [weak self] in self?.meetingLanguage },
        openSettings: { [weak self] in self?.destinations.append($0) },
        launch: { [weak self] character, activity in
          guard let self else { return nil }
          if let launchFailure { return launchFailure }
          launches.append((character.id, activity))
          return nil
        }, dismiss: {}))
  }
  func close() { defaults.removePersistentDomain(forName: domain) }
}

@MainActor func awaitSetup(_ condition: @escaping @MainActor () async -> Bool) async throws {
  for _ in 0..<200 {
    if await condition() { return }
    try await Task.sleep(for: .milliseconds(10))
  }
  Issue.record("Setup did not reach the expected state within two seconds.")
}
