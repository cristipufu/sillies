import AppKit
import SilliesAudio
import SilliesChat
import SilliesCore
import SilliesModelStore
import SilliesTextModels
import Testing

@testable import SilliesApp

@Test @MainActor func setupResumesChoicesAndKeepsCharacterPacksUnchanged() throws {
  let fixture = try SetupFixture()
  defer { fixture.close() }
  let character = try #require(fixture.characters.first(where: { $0.id == "pogo" }))
  fixture.journey.chooseCompanion(character.id)
  fixture.journey.chooseActivity(.talk)
  fixture.journey.move(to: .preparation)
  fixture.journey.deferSetup()
  var custom = CompanionPreferences.Customization()
  custom.language = "fr"
  custom.personality = "A calm companion."
  custom.textModelID = "gemma-4-e4b"
  fixture.preferences.save(custom, for: character)
  let restored = SetupJourney(
    defaults: fixture.defaults, availableIDs: fixture.characters.map(\.id))
  let profiles = CompanionPreferences(defaults: fixture.defaults, characters: fixture.characters)
  #expect(restored.companionID == character.id && restored.activity == .talk)
  #expect(restored.step == .preparation && restored.introduced && !restored.completed)
  #expect(profiles.profile(for: character)?.languageIdentifier == "fr")
  #expect(character.chat?.languageIdentifier != "fr")
  profiles.reset(character)
  #expect(profiles.profile(for: character) == character.chat)
  #expect(profiles.customization(for: character.id).textModelID == nil)
}

@Test @MainActor func setupListsAllTalkBlockersWithoutCapturingOrSpeaking() async throws {
  let fixture = try SetupFixture(
    reply: .init(notice: "Choose a reply model"), voice: .init(notice: "Choose a voice"))
  defer { fixture.close() }
  fixture.permissions.granted.withLock { $0 = false }
  let model = fixture.makePresentation()
  defer { model.stop() }
  model.chooseActivity(.talk)
  try await awaitSetup { !model.isChecking }
  #expect(model.requirements.count == 4)
  #expect(model.requirements.filter { !$0.isSatisfied }.count == 3)
  #expect(!model.canContinue)
  #expect(fixture.capture.starts.withLock { $0 } == 0)
  #expect(await fixture.voice.starts == 0)
  let mic = try #require(model.requirements.first { $0.id == .microphone })
  model.resolve(mic)
  try await awaitSetup {
    model.requirements.first { $0.id == .microphone }?.state == .ready
  }
  #expect(model.requirements.filter { !$0.isSatisfied }.count == 2)
}

@Test @MainActor func directChatBypassesSetupAndIgnoresOptionalVoiceRequirements() async throws {
  let fixture = try SetupFixture(voice: .init(notice: "No voice installed"))
  defer { fixture.close() }
  fixture.permissions.granted.withLock { $0 = false }
  let model = fixture.makePresentation()
  defer { model.stop() }
  model.openConversation(.chat)
  try await awaitSetup { fixture.launches.count == 1 }
  #expect(fixture.launches.first?.1 == .chat)
  #expect(fixture.destinations.isEmpty)
  #expect(fixture.capture.starts.withLock { $0 } == 0)
  #expect(model.journey.completed)
}

@Test @MainActor func directTalkRoutesToSetupAndMeetingsKeepNotesOptional() async throws {
  let fixture = try SetupFixture(
    reply: .init(notice: "Reply model unavailable"), voice: .init(notice: "Voice unavailable"))
  defer { fixture.close() }
  let model = fixture.makePresentation()
  defer { model.stop() }
  model.openConversation(.talk)
  try await awaitSetup { fixture.destinations == [.setup] }
  #expect(fixture.launches.isEmpty && !model.journey.completed)
  model.chooseActivity(.meetings)
  try await awaitSetup { !model.isChecking }
  #expect(model.canContinue)
  #expect(model.requirements.first { $0.id == .replyModel }?.isOptional == true)
  #expect(!model.requirements.contains { $0.id == .voice })
}

@Test @MainActor func stoppedSetupCannotLaunchFromLateReadiness() async throws {
  let fixture = try SetupFixture()
  defer { fixture.close() }
  let model = fixture.makePresentation()
  await fixture.reply.holdNextCheck()
  model.openConversation(.chat)
  try await awaitSetup { await fixture.reply.checks >= 1 }
  model.move(to: .activity)
  await fixture.reply.releaseCheck()
  try await Task.sleep(for: .milliseconds(30))
  #expect(fixture.launches.isEmpty && fixture.destinations.isEmpty)
  #expect(!model.isLaunching && !model.isChecking)
  #expect(model.journey.step == .activity)
}

@Test @MainActor func microphoneTrialJoinsTeardownAndSettingsCloseStopsIt() async throws {
  let fixture = try SetupFixture()
  defer { fixture.close() }
  let model = fixture.makePresentation()
  fixture.capture.held.withLock { $0 = true }
  model.chooseActivity(.talk)
  try await awaitSetup { !model.isChecking }
  model.testMicrophone()
  try await awaitSetup { fixture.capture.starts.withLock { $0 } == 1 }
  let lifecycle = SettingsWindowLifecycle(stop: model.stop, refresh: model.refresh)
  lifecycle.windowWillClose(Notification(name: NSWindow.willCloseNotification))
  #expect(model.audio.phase == .stopping)
  model.testMicrophone()
  #expect(fixture.capture.starts.withLock { $0 } == 1)
  fixture.capture.release()
  try await awaitSetup { model.audio.phase == .idle }
  #expect(fixture.capture.finishes.withLock { $0 } == 1)
  #expect(model.audio.failure == nil)
}

@Test @MainActor func malformedSetupPreferencesRecoverWithoutLosingOtherPreferences() throws {
  let fixture = try SetupFixture()
  defer { fixture.close() }
  fixture.defaults.set(Data("invalid".utf8), forKey: "setupJourney")
  fixture.defaults.set(Data("invalid".utf8), forKey: "companionProfiles")
  fixture.defaults.set("night", forKey: "unrelated")
  let restored = SetupJourney(defaults: fixture.defaults, availableIDs: ["pogo"])
  let profiles = CompanionPreferences(defaults: fixture.defaults, characters: fixture.characters)
  #expect(restored.companionID == "pogo" && restored.step == .companion)
  #expect(profiles.error != nil && profiles.values.isEmpty)
  #expect(fixture.defaults.string(forKey: "unrelated") == "night")
}

@Test @MainActor func setupVoiceTrialJoinsPlaybackStopBeforeLaunchingTalk() async throws {
  let fixture = try SetupFixture()
  defer { fixture.close() }
  let model = fixture.makePresentation()
  defer { model.stop() }
  model.chooseActivity(.talk)
  try await awaitSetup { !model.isChecking }
  await fixture.voice.holdStop()
  model.testVoice(text: "Hello!")
  try await awaitSetup { await fixture.voice.isStopping }
  #expect(model.audio.phase == .stopping)
  model.testVoice(text: "Another preview")
  #expect(await fixture.voice.starts == 1)
  model.complete()
  #expect(fixture.launches.isEmpty)
  await fixture.voice.releaseStop()
  try await awaitSetup { fixture.launches.count == 1 }
  #expect(fixture.launches.first?.1 == .talk && model.audio.phase == .idle)
}

@Test @MainActor func setupCancelledVoiceTrialDrainsPlaybackAndAllowsRetry() async throws {
  let fixture = try SetupFixture()
  defer { fixture.close() }
  let model = fixture.makePresentation()
  defer { model.stop() }
  model.chooseActivity(.talk)
  try await awaitSetup { !model.isChecking }
  await fixture.voice.holdStop()
  await fixture.voice.cancelNextSpeech()
  model.testVoice(text: "Hello!")
  try await awaitSetup { await fixture.voice.isStopping }
  #expect(model.audio.phase == .stopping)
  #expect(model.audio.failure == nil && !model.audio.heardVoice)
  model.testVoice(text: "Another preview")
  #expect(await fixture.voice.starts == 1)
  await fixture.voice.releaseStop()
  // Ensure cleanup even when a regression leaves the cancelled operation active.
  if model.audio.phase == .voice { model.audio.stop() }
  try await awaitSetup { model.audio.phase == .idle }
  model.testVoice(text: "Try again")
  try await awaitSetup { model.audio.phase == .idle && model.audio.heardVoice }
  #expect(await fixture.voice.starts == 2 && model.audio.failure == nil)
}

@Test @MainActor func setupVoiceCreditFollowsPlaybackAndRejectsStoppedCallbacks() async throws {
  let fixture = try SetupFixture()
  defer { fixture.close() }
  let model = fixture.makePresentation()
  defer { model.stop() }
  model.chooseActivity(.talk)
  try await awaitSetup { !model.isChecking }
  await fixture.voice.holdSpeech()
  model.testVoice(text: "Hello!")
  try await awaitSetup { await fixture.voice.starts == 1 }
  let credit = ModelAttribution(
    text: "Voice by Underdog Woof", url: try #require(URL(string: "https://underdog.ai")))
  await fixture.voice.emitPlayback(.attribution(credit))
  try await awaitSetup { model.audio.voiceAttribution == credit }
  model.audio.stop()
  try await awaitSetup { model.audio.phase == .idle }
  await fixture.voice.emitPlayback(.attribution(nil))
  await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
    MainRunLoopDelivery.perform { continuation.resume() }
  }
  #expect(model.audio.voiceAttribution == credit)
}

@Test @MainActor func companionBackendOverrideNeverChangesTheAppDefault() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: root) }
  let environment = TextModelEnvironment(
    store: ModelStore(root: root), preference: .init(selectedID: "apple", save: { _ in }),
    providers: [])
  let manifest = try #require(try await environment.modelCatalog().manifests.first)
  _ = await environment.backend(overriding: manifest.modelID)
  #expect(await environment.selectedID() == "apple")
  await environment.stop()
}

@Test @MainActor func setupKeepsBusyLaunchRecoverableAndRevalidatesBeforeRetrying() async throws {
  let fixture = try SetupFixture()
  defer { fixture.close() }
  fixture.launchFailure = .init(category: .captureUnavailable, message: "Another session is active")
  let model = fixture.makePresentation()
  defer { model.stop() }
  model.openConversation(.chat)
  try await awaitSetup { model.failure != nil }
  #expect(fixture.destinations == [.setup])
  #expect(!fixture.journey.completed && fixture.launches.isEmpty)
  fixture.launchFailure = nil
  model.complete()
  try await awaitSetup { fixture.launches.count == 1 }
  #expect(model.failure == nil && fixture.journey.completed)
}

@Test @MainActor func setupRefreshKeepsChecklistVisibleAndUsesMeetingLanguage() async throws {
  let fixture = try SetupFixture()
  defer { fixture.close() }
  let model = fixture.makePresentation()
  defer { model.stop() }
  model.chooseActivity(.talk)
  try await awaitSetup { !model.isChecking }
  await fixture.reply.holdNextCheck()
  model.refresh()
  #expect(model.isChecking && model.requirements.count == 4 && !model.canContinue)
  try await awaitSetup { await fixture.reply.checks == 2 }
  await fixture.reply.releaseCheck()
  try await awaitSetup { !model.isChecking }
  fixture.meetingLanguage = nil
  model.chooseActivity(.meetings)
  try await awaitSetup { !model.isChecking }
  #expect(!model.canContinue)
  #expect(model.requirements.first { $0.id == .recognition }?.state == .needsAction)
  fixture.meetingLanguage = "en"
  model.refresh()
  try await awaitSetup { !model.isChecking }
  #expect(model.canContinue)
}

@Test @MainActor func setupRejectsInvalidSavedProfilesAndUnknownCompanions() throws {
  let fixture = try SetupFixture()
  defer { fixture.close() }
  let first = try #require(fixture.characters.first)
  let other = try #require(fixture.characters.last)
  var invalid = CompanionPreferences.Customization()
  invalid.personality = String(
    repeating: "x", count: CharacterChatProfile.maximumPersonalityCharacters + 1)
  var valid = CompanionPreferences.Customization()
  valid.language = "de"
  fixture.defaults.set(
    try JSONEncoder().encode([first.id: invalid, other.id: valid]), forKey: "companionProfiles")
  let loaded = CompanionPreferences(defaults: fixture.defaults, characters: fixture.characters)
  #expect(loaded.profile(for: first) == first.chat)
  #expect(loaded.profile(for: other)?.languageIdentifier == "de")
  #expect(loaded.error != nil)
  let previous = fixture.journey.companionID
  fixture.journey.chooseCompanion("missing-companion")
  #expect(fixture.journey.companionID == previous)
}

@Test @MainActor func conversationAdmissionReportsBusyWritingWithoutStartingChat() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: root) }
  let skills = SkillCoordinator(vault: SessionVaultStore(directory: root))
  skills.canStartAudio = { false }
  #expect(
    skills.startConversation(.chat, for: "pogo", name: "Pogo")?.category == .captureUnavailable)
  #expect(skills.activeChatSession == nil)
  skills.canStartAudio = { true }
  skills.isAudioReserved = { true }
  #expect(skills.hasActiveRecording)
  #expect(
    skills.startConversation(.talk, for: "pogo", name: "Pogo")?.category == .captureUnavailable)
  #expect(skills.activeChatSession == nil)
  skills.isAudioReserved = { false }
  #expect(!skills.hasActiveRecording)
  await skills.shutdown()
}

@Test @MainActor func setupReplyRecoveryEditsOnlyTheCompanionsModelOverride() async throws {
  let fixture = try SetupFixture()
  defer { fixture.close() }
  let model = fixture.makePresentation()
  defer { model.stop() }
  let character = try #require(model.character)
  var custom = CompanionPreferences.Customization()
  custom.textModelID = "missing-checkpoint"
  custom.personality = "Quiet and thoughtful"
  fixture.preferences.save(custom, for: character)
  model.refresh()
  try await awaitSetup { !model.isChecking }
  model.resolve(try #require(model.requirements.first { $0.id == .replyModel }))
  #expect(model.isProfileExpanded && fixture.destinations.isEmpty)
  model.useDefaultReplyModel()
  #expect(model.replyModelOverride == nil)
  #expect(model.profile?.personality == custom.personality)
}

@Test @MainActor func conversationSettingsActionsOpenTheirNamedPageAndPreserveModelOverrides()
  throws
{
  let fixture = try SetupFixture()
  defer { fixture.close() }
  let model = fixture.makePresentation()
  defer { model.stop() }
  let navigation = SettingsNavigation()
  let destinations: [(ChatNotice.SettingsDestination, SettingsDestination)] = [
    (.textModels, .intelligence), (.voices, .voices), (.recognition, .speech),
  ]
  for (request, destination) in destinations {
    navigation.returnsToSetup = true
    navigation.showConversationSettings(request, setup: model)
    #expect(navigation.destination == destination && !navigation.returnsToSetup)
  }
  let character = try #require(model.character)
  var custom = CompanionPreferences.Customization()
  custom.textModelID = "missing-checkpoint"
  custom.personality = "Quiet and thoughtful"
  fixture.preferences.save(custom, for: character)
  navigation.showConversationSettings(.textModels, setup: model)
  #expect(navigation.destination == .companions)
  #expect(navigation.companionsPage == .profile && navigation.selectedCompanionID == character.id)
  for (request, destination) in destinations.dropFirst() {
    navigation.showConversationSettings(request, setup: model)
    #expect(navigation.destination == destination)
  }
  #expect(fixture.preferences.customization(for: character.id) == custom)
  #expect(fixture.launches.isEmpty && fixture.capture.starts.withLock { $0 } == 0)
}
