import Foundation
import Observation
import SilliesChat
import SilliesCore

/// Owns the guided journey, revalidation and preview lifetime; views only issue actions.
@MainActor @Observable final class SetupPresentation {
  struct Actions {
    let services: (String) -> ChatServices
    let isGranted: @Sendable (SessionFailure.RecoveryAction) async -> Bool
    let requestPermission: @MainActor (SessionFailure.RecoveryAction) async -> Void
    let meetingLanguage: () async throws -> String?
    let openSettings: (SettingsDestination) -> Void
    let launch: (CharacterDefinition, SetupActivity) -> SessionFailure?
    let dismiss: () -> Void
  }
  let journey: SetupJourney
  let profiles: CompanionPreferences
  let characters: [CharacterDefinition]
  let audio: SetupAudioPreview
  private(set) var requirements: [SetupRequirement] = []
  private(set) var isChecking = false
  private(set) var isLaunching = false
  private(set) var failure: SessionFailure?
  var isProfileExpanded = false
  private var microphoneLanguage: String?
  @ObservationIgnored private let actions: Actions
  @ObservationIgnored private var refreshTask: Task<Void, Never>?
  @ObservationIgnored private var actionTask: Task<Void, Never>?
  @ObservationIgnored private var generation = UUID()
  @ObservationIgnored private var actionGeneration = UUID()
  var character: CharacterDefinition? { characters.first { $0.id == journey.companionID } }
  var profile: CharacterChatProfile? { character.flatMap { profiles.profile(for: $0) } }
  var replyModelOverride: String? { profiles.customization(for: journey.companionID).textModelID }
  var canContinue: Bool {
    character != nil && !isChecking && !isLaunching
      && (journey.activity == .companions
        || !requirements.isEmpty && requirements.allSatisfy(\.isSatisfied))
  }

  init(
    journey: SetupJourney, profiles: CompanionPreferences, characters: [CharacterDefinition],
    audio: SetupAudioPreview, actions: Actions
  ) {
    self.journey = journey
    self.profiles = profiles
    self.characters = characters
    self.audio = audio
    self.actions = actions
  }

  func chooseCompanion(_ id: String) {
    guard characters.contains(where: { $0.id == id }) else { return }
    audio.stop()
    cancelAction()
    journey.chooseCompanion(id)
    requirements = []
    refresh()
  }
  func chooseActivity(_ activity: SetupActivity) {
    audio.stop()
    cancelAction()
    journey.chooseActivity(activity)
    requirements = []
    refresh()
  }
  func move(to step: SetupJourney.Step) {
    stop()
    journey.move(to: step)
    if step == .preparation { refresh() }
  }
  func refresh() {
    refreshTask?.cancel()
    generation = UUID()
    let token = generation
    guard let profile else {
      requirements = []
      isChecking = false
      return
    }
    isChecking = true
    let activity = journey.activity
    let reader = SetupReadiness(
      services: actions.services(journey.companionID), isGranted: actions.isGranted,
      meetingLanguage: actions.meetingLanguage)
    refreshTask = Task { [weak self] in
      let result = await reader.evaluate(activity: activity, language: profile.languageIdentifier)
      guard let self, self.generation == token, !Task.isCancelled else { return }
      self.requirements = result.requirements
      self.microphoneLanguage = result.microphoneLanguage
      self.isChecking = false
      self.refreshTask = nil
    }
  }

  func resolve(_ requirement: SetupRequirement) {
    if requirement.id == .replyModel, replyModelOverride != nil {
      isProfileExpanded = true
      return
    }
    switch requirement.action {
    case .settings(let destination):
      audio.stop()
      actions.openSettings(destination)
    case .permission(let permission):
      guard actionTask == nil else { return }
      let token = UUID()
      actionGeneration = token
      actionTask = Task { [weak self, actions] in
        await actions.requestPermission(permission)
        guard let self, self.actionGeneration == token, !Task.isCancelled else { return }
        self.actionTask = nil
        self.refresh()
      }
    }
  }

  func useDefaultReplyModel() {
    guard let character else { return }
    var customization = profiles.customization(for: character.id)
    customization.textModelID = nil
    profiles.save(customization, for: character)
    refresh()
  }

  func testMicrophone() {
    guard !isChecking, let microphoneLanguage else { return }
    audio.testMicrophone(
      services: actions.services(journey.companionID), language: microphoneLanguage)
  }
  func testVoice(text: String) {
    guard let profile else { return }
    audio.testVoice(services: actions.services(journey.companionID), profile: profile, text: text)
  }
  func complete() {
    guard canContinue else { return }
    requestLaunch(.guided)
  }

  func openConversation(_ mode: ConversationMode) {
    stop()
    journey.chooseActivity(mode == .talk ? .talk : .chat)
    journey.move(to: .preparation)
    requestLaunch(.direct)
  }

  private enum LaunchPresentation { case guided, direct }

  private func requestLaunch(_ presentation: LaunchPresentation) {
    guard actionTask == nil, let character, let profile else { return }
    generation = UUID()
    refreshTask?.cancel()
    refreshTask = nil
    isChecking = false
    let activity = journey.activity
    let token = UUID()
    actionGeneration = token
    isLaunching = true
    failure = nil
    actionTask = Task { [weak self] in
      guard let self else { return }
      await self.audio.finish()
      guard !Task.isCancelled, self.actionGeneration == token else { return }
      // The device/model may have changed during the preview's teardown.
      let readiness = await SetupReadiness(
        services: self.actions.services(character.id), isGranted: self.actions.isGranted,
        meetingLanguage: self.actions.meetingLanguage
      ).evaluate(activity: activity, language: profile.languageIdentifier)
      guard !Task.isCancelled, self.actionGeneration == token else { return }
      self.requirements = readiness.requirements
      self.microphoneLanguage = readiness.microphoneLanguage
      self.isLaunching = false
      self.actionTask = nil
      guard readiness.requirements.allSatisfy(\.isSatisfied) else {
        if presentation == .direct { self.actions.openSettings(.setup) }
        return
      }
      self.failure = self.actions.launch(character, activity)
      if self.failure == nil {
        self.journey.complete()
      } else if presentation == .direct {
        self.actions.openSettings(.setup)
      }
    }
  }
  func deferSetup() {
    journey.deferSetup()
    stop()
    actions.dismiss()
  }
  func stop() {
    generation = UUID()
    refreshTask?.cancel()
    refreshTask = nil
    cancelAction()
    isChecking = false
    isLaunching = false
    audio.stop()
  }

  private func cancelAction() {
    actionGeneration = UUID()
    actionTask?.cancel()
    actionTask = nil
    isLaunching = false
    failure = nil
  }
}
