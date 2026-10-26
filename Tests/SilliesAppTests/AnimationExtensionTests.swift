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

@Test @MainActor func sessionVaultPreparesImagesAsynchronouslyWithoutBlockingViews() async throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("sillies-vault-img-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionVaultStore(directory: directory)
  let context = try #require(
    CGContext(
      data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
  let cgImage = try #require(context.makeImage())
  let record = SessionRecord(
    kind: .snap, characterID: "mochi", characterName: "Mochi", appName: "Preview",
    summary: "Captured")
  store.add(record, image: cgImage)
  let stored = try #require(store.records.first)
  // Immediately available in memory before ioQueue even finishes writing the PNG.
  #expect(store.cachedImage(for: stored) != nil)
  store.flush()

  let reloaded = SessionVaultStore(directory: directory)
  let reloadedRecord = try #require(reloaded.records.first)
  #expect(reloaded.cachedImage(for: reloadedRecord) == nil)
  reloaded.prepareImage(for: reloadedRecord)
  let deadline = ContinuousClock.now.advanced(by: .seconds(1))
  while reloaded.cachedImage(for: reloadedRecord) == nil, ContinuousClock.now < deadline {
    try await Task.sleep(for: .milliseconds(2))
  }
  #expect(reloaded.cachedImage(for: reloadedRecord) != nil)
}

@Test @MainActor func companionHUDCachesLayoutSizeAcrossFrameAndAudioUpdates() throws {
  let hud = CompanionHUDController()
  defer { hud.close() }
  let target = WindowTargetCandidate(
    windowID: 12, processID: 34, appName: "Xcode",
    frame: CGRect(x: 100, y: 100, width: 800, height: 600))
  let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
  for frame in 0..<120 {
    let state = CompanionBindingState.active(
      target: target, skill: .listen, startedAt: 10,
      statusDetail: "00:\(String(format: "%02d", frame % 60)) · Listening to Xcode…",
      audioLevel: Double(frame % 10) * 0.1)
    hud.update(
      state: state,
      companionPoint: CGPoint(x: 300 + Double(frame), y: 700),
      characterSize: 64,
      visibleFrame: screen)
  }
  #expect(hud.layoutMeasurements == 1)

  // Equal-length strings with wider proportional glyphs must invalidate the layout cache
  // and re-measure so the HUD panel never clips wider text.
  let narrow = "00:12 · iiiiiiiiiiiiiiiiiii"
  let wide = "00:12 · WWWWWWWWWWWWWWWWWWW"
  #expect(narrow.count == wide.count)
  hud.update(
    state: .active(
      target: target, skill: .listen, startedAt: 10, statusDetail: narrow, audioLevel: 0),
    companionPoint: CGPoint(x: 300, y: 700),
    characterSize: 64,
    visibleFrame: screen)
  let measurementsAfterNarrow = hud.layoutMeasurements
  let narrowWidth = try #require(hud.currentPanelSize?.width)
  hud.update(
    state: .active(
      target: target, skill: .listen, startedAt: 10, statusDetail: wide, audioLevel: 0),
    companionPoint: CGPoint(x: 300, y: 700),
    characterSize: 64,
    visibleFrame: screen)
  let wideWidth = try #require(hud.currentPanelSize?.width)
  #expect(hud.layoutMeasurements == measurementsAfterNarrow + 1)
  #expect(wideWidth > narrowWidth)
}

@Test @MainActor func stashingDuringActiveSkillPreservesActiveSessionAndSavesBoth() throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("sillies-stash-active-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  let coordinator = SkillCoordinator(vault: vault)
  let target = WindowTargetCandidate(
    windowID: 55, processID: 101, appName: "Xcode",
    frame: CGRect(x: 100, y: 100, width: 800, height: 600))

  coordinator.startSkill(.focus, for: "mochi", companionName: "Mochi", target: target)
  coordinator.recordStash(
    items: ["https://github.com/cristipufu/sillies"],
    for: "mochi", companionName: "Mochi", currentTarget: target)

  // Active Focus session must remain active after stashing.
  if case .active(let activeTarget, let skill, _, let detail, _) = coordinator.binding(for: "mochi")
  {
    #expect(activeTarget.windowID == 55)
    #expect(skill == .focus)
    #expect(detail.contains("Stashed"))
  } else {
    Issue.record("Expected Focus session to remain active after stashing")
  }

  // Stopping the Focus session must still persist the Focus record alongside the Stash record.
  coordinator.stopSkill(for: "mochi")
  #expect(vault.records.count == 2)
  #expect(vault.records.contains { $0.kind == .stash })
  #expect(vault.records.contains { $0.kind == .focus })
}

private actor DelayedSnapshotProbe {
  private var continuation: CheckedContinuation<[CGWindowID: WindowTargetSnapshot], Never>?
  private(set) var requestedIDs: Set<CGWindowID> = []

  func load(_ ids: Set<CGWindowID>) async -> [CGWindowID: WindowTargetSnapshot] {
    requestedIDs = ids
    return await withCheckedContinuation { continuation = $0 }
  }

  func finish(_ snapshots: [CGWindowID: WindowTargetSnapshot]) {
    continuation?.resume(returning: snapshots)
    continuation = nil
  }
}

@Test @MainActor func staleMetadataReplyDoesNotDismissNewSelectionPrompt() async throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("sillies-stale-tick-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let probe = DelayedSnapshotProbe()
  let vault = SessionVaultStore(directory: directory)
  let coordinator = SkillCoordinator(
    vault: vault,
    snapshotLoader: { ids, _ in await probe.load(ids) })
  defer { coordinator.stopAll() }

  let firstTarget = WindowTargetCandidate(
    windowID: 10, processID: 1, appName: "Safari",
    frame: CGRect(x: 0, y: 0, width: 600, height: 400))
  let secondTarget = WindowTargetCandidate(
    windowID: 20, processID: 2, appName: "Terminal",
    frame: CGRect(x: 200, y: 200, width: 600, height: 400))

  coordinator.presentSelectionPrompt(for: "mochi", companionName: "Mochi", target: firstTarget)
  coordinator.pollBoundWindows()
  let deadline = ContinuousClock.now.advanced(by: .seconds(1))
  while await probe.requestedIDs.isEmpty, ContinuousClock.now < deadline {
    try await Task.sleep(for: .milliseconds(1))
  }
  #expect(await probe.requestedIDs == [10])

  // Switch Mochi to a new target window while the old metadata request for window 10 is in flight.
  coordinator.presentSelectionPrompt(for: "mochi", companionName: "Mochi", target: secondTarget)
  await probe.finish([
    10: WindowTargetSnapshot(frame: firstTarget.frame, title: "Safari")
  ])
  try await Task.sleep(for: .milliseconds(10))

  if case .awaitingSelection(let boundTarget, _) = coordinator.binding(for: "mochi") {
    #expect(boundTarget.windowID == 20)
  } else {
    Issue.record("Stale tick reply dismissed the new selection prompt")
  }
}

@Test @MainActor func sessionVaultDownsamplesPreviewsAndEnforcesByteBudget() throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("sillies-vault-budget-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionVaultStore(directory: directory)
  let context = try #require(
    CGContext(
      data: nil, width: 2560, height: 1440, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
  let largeImage = try #require(context.makeImage())

  for index in 0..<24 {
    let record = SessionRecord(
      kind: .snap, characterID: "mochi", characterName: "Mochi",
      appName: "Display \(index)", summary: "Snapshot \(index)")
    store.add(record, image: largeImage)
  }

  #expect(store.totalCachedImageBytes <= SessionVaultStore.maxCacheBytes)
  if let latest = store.records.first, let preview = store.cachedImage(for: latest) {
    #expect(
      max(preview.size.width, preview.size.height)
        <= CGFloat(SessionVaultStore.maxPreviewPixelDimension))
  } else {
    Issue.record("Expected latest snapshot preview to be cached")
  }
}
