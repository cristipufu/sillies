import AppKit
import SilliesCore
import SilliesWriting

@MainActor
final class CommandDispatcher {
  struct Companion {
    let id: String
    let name: String
    let position: CGPoint
  }
  struct Context {
    let companion: Companion
    let target: WindowTargetCandidate?
  }
  struct Environment {
    let isAvailable: () -> Bool
    let companion: () -> Companion?
    let openVault: () -> Void
    let togglePause: () -> Void
    let saveClipboard: (String) -> Void
  }
  @MainActor struct Targeting {
    var current: () -> FrontmostApplication? = { FrontmostApplication.current }
    var resolve: (FrontmostApplication, Double) async -> WindowTargetCandidate? = {
      await FrontmostWindowTargeting().resolve($0, primaryScreenTop: $1)
    }
  }
  private let skills: SkillCoordinator
  private let environment: Environment
  private let targeting: Targeting
  private let feedback: StashFeedbackController
  private var pending: Task<Void, Never>?
  private var generation = UUID()
  var onWritingCommand: ((AppCommand) -> Bool)?
  var onStopWriting: (() -> Void)?
  var onReleaseDictation: (() -> Void)?

  init(
    skills: SkillCoordinator, environment: Environment, targeting: Targeting = .init(),
    appearance: ThemeEnvironment
  ) {
    self.skills = skills
    self.environment = environment
    self.targeting = targeting
    feedback = StashFeedbackController(appearance: appearance)
  }

  func perform(_ command: AppCommand, context: Context? = nil) {
    if command == .openVault {
      environment.openVault()
      return
    }
    if command == .togglePause {
      environment.togglePause()
      return
    }
    if command == .dictationHistory, onWritingCommand?(command) == true { return }
    guard environment.isAvailable() else {
      feedback.showMessage(
        String(
          localized:
            "Companions are paused or unavailable in this app. Resume them in the Sillies menu."),
        at: .init(position: NSEvent.mouseLocation))
      return
    }
    if onWritingCommand?(command) == true { return }
    if command.skill?.keepsCompanionStill == true, skills.hasActiveCaptureSkill {
      skills.openActiveSession()
      return
    }
    if command.skill?.keepsCompanionStill == true, !skills.canStartAudio() {
      feedback.showMessage(
        String(localized: "Finish dictation or writing before starting another session."),
        at: .init(position: NSEvent.mouseLocation))
      return
    }
    guard let companion = context?.companion ?? environment.companion() else {
      feedback.showMessage(
        String(localized: "Choose an available companion first."),
        at: .init(position: NSEvent.mouseLocation))
      return
    }
    if command == .saveClipboard {
      environment.saveClipboard(companion.id)
      return
    }
    guard let skill = command.skill else { return }
    if let context {
      start(skill, context: context)
      return
    }
    if !skill.requiresWindow {
      start(skill, context: .init(companion: companion, target: nil))
      return
    }
    guard let app = targeting.current() else {
      feedback.showMessage(
        String(localized: "Focus the window you want to use first."),
        at: .init(position: companion.position))
      return
    }
    cancelPending()
    let token = generation
    let top = NSScreen.screens.first?.frame.maxY ?? 0
    pending = Task { [weak self, targeting] in
      let target = await targeting.resolve(app, top)
      guard !Task.isCancelled, let self, self.generation == token,
        targeting.current() == app, self.environment.isAvailable()
      else { return }
      guard let target else {
        self.feedback.showMessage(
          String(localized: "No usable foreground window was found."),
          at: .init(position: companion.position))
        return
      }
      self.start(skill, context: .init(companion: companion, target: target))
    }
  }

  private func start(_ skill: CompanionSkillKind, context: Context) {
    if skill.keepsCompanionStill, skills.hasActiveCaptureSkill {
      skills.openActiveSession()
      return
    }
    skills.startSkill(
      skill, for: context.companion.id, companionName: context.companion.name,
      target: context.target)
  }

  func cancelPending() {
    generation = UUID()
    pending?.cancel()
    pending = nil
  }

  func stop() {
    cancelPending()
    onStopWriting?()
    feedback.close()
  }

  func release(_ command: AppCommand) {
    if command == .holdDictation { onReleaseDictation?() }
  }
}
