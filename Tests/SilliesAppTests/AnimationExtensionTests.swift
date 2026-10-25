import QuartzCore
import SilliesCore
import Testing

@testable import SilliesApp

@Test @MainActor func characterOverridesDoNotChangeOtherCharacters() {
  let library = AnimationLibrary()
  let rig = CatRig()
  var calls: [String] = []
  library.register("test.dance") { _ in calls.append("shared") }
  library.register("test.dance", characterID: "newcomer") { _ in calls.append("custom") }
  let state = BehaviorState(animation: "test.dance")
  library.apply(state, to: rig, characterID: "newcomer", reducedMotion: false)
  library.apply(state, to: rig, characterID: "mochi", reducedMotion: false)
  #expect(calls == ["custom", "shared"])
}

@Test @MainActor func poseVariantsResolveBeforeCharacterSpecificClips() {
  let library = AnimationLibrary()
  let rig = NinjaRig()
  var climbed = false
  library.register(.climb, characterID: "kiko") { _ in climbed = true }
  rig.setAttachmentPose(.hangingRight)
  library.apply(BehaviorState(animation: .walk), to: rig, characterID: "kiko", reducedMotion: false)
  #expect(climbed)
}

@Test @MainActor func behaviorChangesPreserveIndependentPresentationTransitions() {
  let rig = CatRig()
  let view = CompanionView(rig: rig, size: 64)
  let transition = CABasicAnimation(keyPath: "opacity")
  transition.duration = 1
  view.presentationLayer.add(transition, forKey: "presentation")
  AnimationLibrary().apply(
    BehaviorState(animation: .walk), to: rig, characterID: "mochi", reducedMotion: false)
  #expect(view.presentationLayer.animation(forKey: "presentation") != nil)
}

@Test @MainActor func behaviorChangesPreserveWindowInertiaButStoppingClearsIt() {
  let rig = CatRig()
  rig.workspaceFeedback(lean: 0.1, stretch: 0.04, settling: true)
  AnimationLibrary().apply(
    BehaviorState(animation: .walk), to: rig, characterID: "mochi", reducedMotion: false)
  #expect(rig.workspaceMotion.animation(forKey: "workspaceFeedback") != nil)
  rig.resetPose()
  #expect(rig.workspaceMotion.animationKeys() == nil)
}

@Test @MainActor func customTransitionsAndNewCharactersValidateWithoutControllerChanges() throws {
  let definition = CharacterDefinition(
    id: "newcomer", name: "Newcomer", subtitle: "", bio: "", renderer: "new.art",
    accent: "AABBCC", speed: 20,
    reactions: [
      ReactionDefinition(id: "rest", event: .ambient, animation: "new.rest", duration: 5)
    ],
    transitions: CharacterTransitions(
      enter: TransitionDefinition(animation: "new.arrive", duration: 0.2)))
  let catalog = try CharacterCatalog(characters: [definition])
  let renderers = RendererRegistry()
  let animations = AnimationLibrary()
  let transitions = TransitionLibrary()
  #expect(throws: CharacterDefinition.ValidationError.self) {
    try catalog.validateAssets(
      renderers: renderers, animations: animations, transitions: transitions)
  }
  renderers.register("new.art", factory: CatRig.init)
  animations.register("new.rest", characterID: "newcomer") { _ in }
  transitions.register("new.arrive") { context in
    let animation = CABasicAnimation(keyPath: "opacity")
    animation.duration = context.duration
    animation.fromValue = context.fromOpacity
    animation.toValue = context.targetOpacity
    return animation
  }
  try catalog.validateAssets(renderers: renderers, animations: animations, transitions: transitions)
  animations.registerVariant("new.rest", pose: .hangingLeft, clip: "missing.side.clip")
  #expect(throws: CharacterDefinition.ValidationError.self) {
    try catalog.validateAssets(
      renderers: renderers, animations: animations, transitions: transitions)
  }
}

@Test @MainActor func customReducedMotionExpressionAppliesWhenReducedMotionIsActive() {
  let library = AnimationLibrary()
  let rig = CatRig()
  var staticApplied = false
  var animatedApplied = false
  library.register("custom.calm", characterID: "mochi") { _ in
    animatedApplied = true
  }
  library.registerReducedMotion("custom.calm", characterID: "mochi") { target in
    staticApplied = true
    target.delight.opacity = 1
  }
  library.apply(
    BehaviorState(animation: "custom.calm"), to: rig, characterID: "mochi", reducedMotion: true)
  #expect(staticApplied)
  #expect(!animatedApplied)
  #expect(rig.delight.opacity == 1)
}

@MainActor
private final class MockEventProducer: WorkspaceEventProducer {
  var onEvent: ((WorkspaceEvent) -> Void)?
  var isStarted = false
  var isEnabled = false
  func start() { isStarted = true }
  func stop() { isStarted = false }
  func configure(enabled: Bool, tracksWindows: Bool) { isEnabled = enabled }
}

@Test @MainActor func customEventProducerRoutesEventsAndStopsWhenPaused() throws {
  let suiteName = "app.sillies.test.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName) ?? .standard
  defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
  let settings = AppSettings(defaults: defaults)
  settings.followsWindows = false
  let producer = MockEventProducer()
  let controller = try CompanionController(
    settings: settings, useAccessibility: false, eventProducers: [producer])
  controller.start()
  #expect(producer.isStarted)
  #expect(producer.isEnabled)
  producer.onEvent?(WorkspaceEvent(.pet, at: ProcessInfo.processInfo.systemUptime))
  #expect(
    (controller.playedAnimations[.happy] ?? 0) + (controller.playedAnimations[.wave] ?? 0) > 0)
  settings.paused = true
  #expect(!producer.isEnabled)
  controller.stop()
  #expect(!producer.isStarted)
}

@Test @MainActor func pickedUpCompanionRendersUnclippedAboveFocusedWindow() throws {
  let definition = CharacterDefinition(
    id: "mochi", name: "Mochi", subtitle: "", bio: "", renderer: "cat",
    accent: "AABBCC", speed: 20,
    reactions: [
      ReactionDefinition(id: "rest", event: .ambient, animation: .idle, duration: 5)
    ])
  let pet = CompanionInstance(
    definition: definition, rig: CatRig(), size: 64, seed: 1, transitions: TransitionLibrary())
  let focusedWindow = CGRect(x: 200, y: 200, width: 600, height: 400)
  let display = CGRect(x: 0, y: 0, width: 1440, height: 900)
  pet.view.configureSurface(pose: .standing, window: focusedWindow, display: display)
  pet.isPickedUp = true
  let insideWindow = CGPoint(x: 500, y: 400)
  pet.place(at: insideWindow)
  pet.panel.orderFrontRegardless()
  #expect(pet.panel.frame.intersects(focusedWindow))
  #expect(!pet.view.isProtectedInputPoint(CGPoint(x: insideWindow.x, y: insideWindow.y + 35)))
  #expect(
    pet.view.containsInteractiveArtwork(at: CGPoint(x: insideWindow.x, y: insideWindow.y + 35)))
  pet.presentation.close()
}

@Test @MainActor func sessionVaultPersistsAndReloadsRecords() throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("sillies-vault-test-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionVaultStore(directory: directory)
  let record = SessionRecord(
    kind: .snap,
    characterID: "mochi",
    characterName: "Mochi",
    appName: "Xcode",
    windowTitle: "CompanionController.swift",
    extractedText: "final class CompanionController",
    summary: "• Captured CompanionController.swift")
  store.add(record)
  store.flush()
  #expect(store.records.count == 1)

  let reloaded = SessionVaultStore(directory: directory)
  #expect(reloaded.records.count == 1)
  #expect(reloaded.records.first?.extractedText == "final class CompanionController")
  reloaded.remove(id: record.id)
  reloaded.flush()
  #expect(reloaded.records.isEmpty)
}

@Test @MainActor func skillCoordinatorManagesLifecycleAndPocketStash() throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("sillies-skills-test-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  let coordinator = SkillCoordinator(vault: vault)
  var emittedEvents: [EventKind] = []
  coordinator.onEmitEvent = { _, event in emittedEvents.append(event.kind) }

  let target = WindowTargetCandidate(
    windowID: 42, processID: 100, appName: "Terminal",
    bundleIdentifier: "com.apple.Terminal", windowTitle: "make check",
    frame: CGRect(x: 100, y: 100, width: 700, height: 500))

  coordinator.presentSelectionPrompt(for: "mochi", companionName: "Mochi", target: target)
  #expect(coordinator.binding(for: "mochi").isBound)

  coordinator.startSkill(.focus, for: "mochi", companionName: "Mochi", target: target)
  #expect(emittedEvents.contains(.skillFocus))
  if case .active(let activeTarget, let skill, _, _, _) = coordinator.binding(for: "mochi") {
    #expect(activeTarget.windowID == 42)
    #expect(skill == .focus)
  } else {
    Issue.record("Expected active focus binding")
  }

  coordinator.stopSkill(for: "mochi")
  #expect(emittedEvents.contains(.skillCompleted))
  #expect(vault.records.count == 1)
  #expect(vault.records.first?.kind == .focus)

  coordinator.recordStash(
    items: ["https://example.com/spec", "TODO: ship skills"],
    for: "kiko", companionName: "Kiko", currentTarget: target)
  #expect(emittedEvents.contains(.stashReceived))
  #expect(vault.records.count == 2)
  #expect(vault.records.first?.kind == .stash)

  coordinator.stopAll()
  #expect(!coordinator.binding(for: "mochi").isBound)
  #expect(!coordinator.binding(for: "kiko").isBound)
}

@Test @MainActor func builtinSkillAnimationsApplyInNormalAndReducedMotion() {
  let library = AnimationLibrary()
  let rig = CatRig()
  for animation: AnimationID in [.snap, .listen, .watch, .focus] {
    library.apply(
      BehaviorState(animation: animation), to: rig, characterID: "mochi", reducedMotion: false)
    library.apply(
      BehaviorState(animation: animation), to: rig, characterID: "mochi", reducedMotion: true)
  }
}

@Test @MainActor func desktopModeCompanionsRemainInteractiveAndDraggable() throws {
  let suiteName = "app.sillies.test.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName) ?? .standard
  defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
  let settings = AppSettings(defaults: defaults)
  settings.followsWindows = false
  settings.reduceMotion = true
  let controller = try CompanionController(settings: settings, useAccessibility: false)
  controller.start()
  defer { controller.stop() }

  let attachments = controller.attachmentDiagnostics
  #expect(attachments.count == 2)
  #expect(attachments.allSatisfy { $0.edge == .desktop && $0.visible })
  #expect(!controller.diagnostics.clickThrough)
  for attachment in attachments {
    let bodyPoint = CGPoint(x: attachment.point.x, y: attachment.point.y + 35)
    #expect(controller.interactiveArtworkCount(at: bodyPoint) == 1)
  }
}
