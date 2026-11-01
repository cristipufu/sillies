import AppKit
import SilliesCore

/// Adapts companion menus, HUD actions, and stash drops to skill commands.
@MainActor
final class CompanionSkillControls {
  struct Environment {
    let isRunning: () -> Bool
    let focusedTarget: () -> WindowTargetCandidate?
    let openVault: (UUID?) -> Void
    var openWritingSession: () -> Void = {}
    let performSkill: (CompanionSkillKind, CompanionInstance, WindowTargetCandidate?) -> Void
    let motionChanged: () -> Void
  }
  private let skills: SkillCoordinator
  private let environment: Environment
  private let directMenu: CompanionDirectMenu
  private let feedback: StashFeedbackController
  private var isActive = false
  private var generation = UUID()

  init(skills: SkillCoordinator, environment: Environment, appearance: ThemeEnvironment) {
    self.skills = skills
    self.environment = environment
    feedback = StashFeedbackController(appearance: appearance)
    directMenu = CompanionDirectMenu(appearance: appearance)
    directMenu.onClose = { [weak self] in self?.environment.motionChanged() }
  }

  func start() { isActive = true }

  func dismissMenu(for pet: CompanionInstance) { directMenu.close(for: pet) }

  func stop() {
    isActive = false
    generation = UUID()
    feedback.close()
    directMenu.close()
  }

  func configure(_ pet: CompanionInstance) {
    pet.view.onDoubleClick = { [weak self, weak pet] in
      guard let self, let pet, self.isActive, self.environment.isRunning() else { return }
      self.directMenu.show(for: pet) { [weak self, weak pet] action in
        guard let self, let pet, self.isActive else { return }
        self.perform(action, for: pet, target: nil)
      }
    }
    configureHUD(pet)
    pet.configureStashControls(
      .init(
        menu: { [weak self, weak pet] in
          guard let self, let pet else { return NSMenu() }
          return self.menu(for: pet)
        },
        targetChanged: { [weak self, weak pet] targeted in
          guard let self, self.isActive, let pet, pet.isStashTargeted != targeted else { return }
          pet.setStashTargeted(targeted)
          if targeted {
            self.feedback.showDropTarget(at: pet.position)
          } else {
            self.feedback.hideDropTarget()
          }
          self.environment.motionChanged()
        },
        dropped: { [weak self, weak pet] items in
          guard let self, let pet else { return }
          self.stash(
            items, with: pet, target: pet.attachmentTarget ?? self.environment.focusedTarget())
        }))
  }

  private func configureHUD(_ pet: CompanionInstance) {
    let id = pet.definition.id
    pet.configureSkillControls(
      .init(
        openSession: { [weak self] in self?.skills.openSession(for: id) },
        undoStash: { [weak self] recordID in
          self?.skills.removeRecord(id: recordID)
          self?.skills.unbind(companionID: id)
        },
        stopSkill: { [weak self] in self?.skills.stopSkill(for: id) },
        unbind: { [weak self] in self?.skills.unbind(companionID: id) },
        openVault: { [weak self] in self?.environment.openVault($0) },
        focusWindow: { NSRunningApplication(processIdentifier: $0.processID)?.activate() }))
  }

  private func menu(for pet: CompanionInstance) -> NSMenu {
    let target = pet.attachmentTarget ?? environment.focusedTarget()
    return CompanionActionMenu.make(
      windowName: target?.appName,
      hasAudioSession: skills.hasActiveCaptureSkill || pet.isWritingIndicator
    ) {
      [weak self, weak pet] action in
      guard let self, self.isActive, let pet, self.environment.isRunning() else { return }
      self.perform(action, for: pet, target: target)
    }
  }

  private func perform(
    _ action: CompanionMenuAction, for pet: CompanionInstance, target: WindowTargetCandidate?
  ) {
    switch action {
    case .talk:
      guard canStartConversation(with: pet) else { return }
      skills.startConversation(.talk, for: pet.definition.id, name: pet.definition.name)
    case .skill(.chat):
      guard canStartConversation(with: pet) else { return }
      skills.startConversation(.chat, for: pet.definition.id, name: pet.definition.name)
    case .skill(let skill):
      environment.performSkill(skill, pet, target)
    case .saveClipboard: stash(StashPasteboard.items(from: .general), with: pet, target: target)
    case .openStash: environment.openVault(nil)
    case .openSession:
      if pet.isWritingIndicator {
        environment.openWritingSession()
      } else {
        skills.openActiveSession()
      }
    }
  }

  private func canStartConversation(with pet: CompanionInstance) -> Bool {
    guard skills.activeAudioSession == nil, skills.canStartAudio(), !pet.isWritingIndicator else {
      feedback.showMessage(
        String(localized: "Choose an available companion first."), at: pet.position)
      return false
    }
    return true
  }

  func saveClipboard(with pet: CompanionInstance) {
    stash(
      StashPasteboard.items(from: .general), with: pet,
      target: pet.attachmentTarget ?? environment.focusedTarget())
  }

  private func stash(_ items: [String], with pet: CompanionInstance, target: WindowTargetCandidate?)
  {
    guard isActive, environment.isRunning(), !pet.isWritingIndicator else { return }
    guard
      let id = skills.recordStash(
        items: items, for: pet.definition.id,
        companionName: pet.definition.name, currentTarget: target)
    else {
      feedback.showMessage(String(localized: "Copy text or a link first"), at: pet.position)
      return
    }
    feedback.showMessage(String(localized: "Saving…"), at: pet.position)
    let requestGeneration = generation
    skills.whenPersisted { [weak self, weak pet] error in
      guard let self, self.isActive, self.generation == requestGeneration,
        let pet, self.environment.isRunning()
      else { return }
      if let error {
        self.feedback.showMessage(error, at: pet.position)
        return
      }
      self.feedback.showSaved(
        id, at: pet.position,
        open: { [weak self] in self?.environment.openVault($0) },
        undo: { [weak self] in self?.skills.removeRecord(id: $0) })
    }
  }
}
