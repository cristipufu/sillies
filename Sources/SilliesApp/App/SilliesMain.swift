import AppKit
import Observation
import SilliesAudio
import SilliesChat
import SilliesCore
import SwiftUI

@main
struct SilliesMain {
  @MainActor
  static func main() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.mainMenu = ApplicationMenu.make()
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
  private static let initialVaultWindowSize = NSSize(width: 980, height: 660)
  private static let minVaultWindowSize = NSSize(width: 880, height: 560)
  private static let exportedCharacterPreviewPixels = 512
  private static let exportedCharacterPreviewScale: CGFloat = 4

  private var controller: CompanionController?
  private var statusItem: NSStatusItem?
  private let popover = NSPopover()
  private let controlCenterDismissal = ControlCenterDismissal()
  private var settingsWindow: NSWindow?
  private let settingsNavigation = SettingsNavigation()
  private var speechServices: SpeechServices?
  private var voiceServices: VoiceServices?
  private var appearancePreferences: AppearancePreferences?
  private var languagePreferences: LanguagePreferences?
  private let appearance = ThemeEnvironment()
  private lazy var chatWindow = ChatSessionWindowController(appearance: appearance)
  private let reasoningServices = ReasoningServices()
  private lazy var textModels = TextModelsPresentation(environment: reasoningServices.models)
  private var shortcuts: CommandShortcuts?
  private var writingTools: WritingTools?
  private let loginItems = LoginItemSettings()
  private lazy var audioSessionWindow = AudioSessionWindowController(appearance: appearance)
  private var vaultWindow: NSWindow?
  private var previewWindow: NSWindow?
  private var temporaryPreferencesDomain: String?
  private var playground: WindowPlayground?
  private let automatedRunner = AutomatedLaunchRunner()
  private var isTerminating = false
  private(set) var terminationFlushTask: Task<Void, Never>?
  var onTerminationApproved: @MainActor (NSApplication) -> Void = { sender in
    sender.reply(toApplicationShouldTerminate: true)
  }

  func configureForTesting(controller: CompanionController) {
    self.controller = controller
    self.isTerminating = false
    self.terminationFlushTask = nil
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    do {
      let launch = LaunchConfiguration()
      automatedRunner.armWatchdogIfNeeded(for: launch)
      if launch.runsWritingFixture {
        automatedRunner.startWritingFixture()
        return
      }
      if launch.runsInputFixture {
        automatedRunner.startInputFixture()
        return
      }
      if launch.usesDarkAppearance { NSApp.appearance = NSAppearance(named: .darkAqua) }
      let settings = makeSettings(for: launch)
      chatWindow.prefersReducedMotion = { settings.reduceMotion }
      let skills = try makeSkillCoordinator(for: launch)
      let controller = try CompanionController(
        settings: settings,
        services: .init(
          accessibility: launch.usesAccessibility ? .enabled : .disabled, skills: skills,
          appearance: appearance))
      controller.onOpenVault = { [weak self] recordID in
        self?.showVault(recordID: recordID)
      }
      skills.onOpenAudioSession = { [weak self] in self?.audioSessionWindow.show($0) }
      self.controller = controller
      if let speechServices {
        try configureChat(
          skills: skills, speech: speechServices, characters: controller.catalog.characters)
      }
      if launch.validatesCatalogOnly {
        automatedRunner.validateCatalog(characterCount: controller.catalog.characters.count)
        return
      }
      if launch.isAutomatedRun {
        settings.enabledCharacters = Set(controller.catalog.characters.map(\.id))
      }
      controller.start()
      speechServices?.start()
      if !launch.isAutomatedRun {
        textModels.start()
        voiceServices?.models.start()
      }
      observeModelUpdateActivity()
      if !launch.isAutomatedRun {
        if let speechServices {
          writingTools = WritingTools(
            speech: speechServices, companions: controller,
            services: .init(
              vault: skills.vault, recording: skills, commands: controller.commands,
              reasoning: reasoningServices.reasoning, appearance: appearance))
        }
        let shortcuts = CommandShortcuts()
        shortcuts.onEvent = { [weak controller] command, edge in
          if edge == .pressed {
            controller?.commands.perform(command)
          } else {
            controller?.commands.release(command)
          }
        }
        self.shortcuts = shortcuts
        shortcuts.start()
        observeCommandAvailability()
        _ = Updates.shared
        installStatusItem()
      }
      if launch.showsPreview { showPreview() }
      automatedRunner.appWindowActions = .init(
        prepareControlCenter: { [unowned self] in
          if self.statusItem == nil { self.installStatusItem() }
          return .init(button: self.statusItem?.button, popover: self.popover)
        },
        openSettings: { [unowned self] in
          self.showSettings()
          return self.settingsWindow
        },
        openVault: { [unowned self] in
          self.showVault()
          return self.vaultWindow
        },
        openChat: { [unowned self] in
          self.popover.close()
          skills.makeChatSession = { _, _ in ChatWindowFixture.makeSession() }
          skills.onOpenChatSession = { [unowned self] in
            self.chatWindow.show($0, openSettings: { _ in })
          }
          controller.commands.perform(
            .chat,
            context: .init(
              companion: .init(id: "mochi", name: "Mochi", position: .zero), target: nil))
          return self.chatWindow.window
        })
      automatedRunner.run(
        launch,
        controller: controller,
        openPlayground: { [unowned self] in self.openOrCreatePlayground(for: controller) },
        exportPreviews: { [weak self] directory in self?.exportPreviews(to: directory) })
    } catch {
      let alert = NSAlert()
      alert.messageText = String(localized: "Sillies couldn’t get settled.")
      alert.informativeText = error.localizedDescription
      alert.runModal()
      NSApp.terminate(nil)
    }
  }

  private func makeSettings(for launch: LaunchConfiguration) -> AppSettings {
    let defaults: UserDefaults
    if launch.isAutomatedRun {
      let domain = "app.sillies.test.\(UUID().uuidString)"
      temporaryPreferencesDomain = domain
      defaults = UserDefaults(suiteName: domain) ?? .standard
    } else {
      defaults = .standard
    }
    let settings = AppSettings(defaults: defaults)
    let preferences = AppearancePreferences(defaults: defaults)
    appearancePreferences = preferences
    let language = LanguagePreferences(defaults: defaults)
    languagePreferences = language
    language.start()
    preferences.onChange = { [weak preferences, appearance] in
      NSApp.appearance =
        launch.usesDarkAppearance ? NSAppearance(named: .darkAqua) : preferences?.appearance.native
      appearance.update(
        SilliesTheme(
          definition: preferences?.selectedTheme,
          contrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            ? .increased : .system))
    }
    preferences.start()
    launch.apply(to: settings)
    return settings
  }

  private func observeModelUpdateActivity() {
    guard !isTerminating, let controller, let updates = speechServices?.models.updates else {
      return
    }
    withObservationTracking {
      let active = controller.shouldRun && controller.liveCount > 0
      updates.setActivity(active ? .active : .suspended)
      Task { [models = reasoningServices.models, voices = voiceServices?.environment] in
        await models.setActivity(active ? .active : .suspended)
        if active { await voices?.resume() } else { await voices?.stop() }
      }
    } onChange: { [weak self] in
      Task { @MainActor in self?.observeModelUpdateActivity() }
    }
  }

  private func observeCommandAvailability() {
    guard !isTerminating, let controller, let shortcuts else { return }
    withObservationTracking {
      shortcuts.configure(controller.shouldRun && controller.liveCount > 0 ? .active : .suspended)
    } onChange: { [weak self] in
      Task { @MainActor in self?.observeCommandAvailability() }
    }
  }

  private func configureChat(
    skills: SkillCoordinator, speech: SpeechServices, characters: [CharacterDefinition]
  ) throws {
    let reference = VoicePlaybackReference()
    let voices = try VoiceServices(renderReference: reference.append)
    voiceServices = voices
    let profiles = Dictionary(
      uniqueKeysWithValues: characters.compactMap { character in
        character.chat.map { (character.id, $0) }
      })
    let services = ChatServices(
      captureFactory: speech.conversationCaptureFactory(reference: reference),
      loadLanguages: speech.languages.load,
      conversation: reasoningServices.conversation, speech: voices.speech,
      deliver: { MainRunLoopDelivery.perform($0) })
    skills.makeChatSession = { id, name in
      guard let profile = profiles[id] else { return nil }
      return ChatSession(companionName: name, profile: profile, services: services, companionID: id)
    }
    skills.onOpenChatSession = { [weak self] session in
      self?.chatWindow.show(
        session,
        openSettings: { [weak self] destination in
          self?.settingsNavigation.destination =
            destination == .textModels ? .intelligence : .voices
          self?.showSettings()
        }, renderer: characters.first(where: { $0.id == session.companionID })?.renderer)
    }
  }

  private func makeSkillCoordinator(for launch: LaunchConfiguration) throws -> SkillCoordinator {
    guard launch.isAutomatedRun else {
      let speech = try SpeechServices()
      speechServices = speech
      return SkillCoordinator(
        vault: reasoningServices.makeVault(),
        audio: .init(
          captureFactory: speech.captureFactory, languages: speech.languages,
          reasoning: reasoningServices.reasoning))
    }
    let tempVault = FileManager.default.temporaryDirectory
      .appendingPathComponent("sillies-vault-\(UUID().uuidString)", isDirectory: true)
    let speech = try SpeechServices()
    return SkillCoordinator(
      vault: reasoningServices.makeVault(directory: tempVault),
      audio: .init(
        captureFactory: speech.captureFactory, languages: speech.languages,
        reasoning: reasoningServices.reasoning))
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard !isTerminating else { return .terminateNow }
    guard let controller else {
      cleanupTemporaryPreferences()
      return .terminateNow
    }
    isTerminating = true
    controlCenterDismissal.stop()
    shortcuts?.stop()
    automatedRunner.stopPreview()
    speechServices?.stop()
    textModels.stop()
    voiceServices?.models.stop()
    appearancePreferences?.stop()
    languagePreferences?.stop()
    cleanupTemporaryPreferences()
    let approveTermination = onTerminationApproved
    let (stream, continuation) = AsyncStream<Void>.makeStream()
    terminationFlushTask = Task {
      for await _ in stream { break }
    }
    controller.flushForTermination { [weak self, weak controller] in
      MainActor.assumeIsolated {
        controller?.drainPreviewsForTermination()
        let complete: @MainActor @Sendable () -> Void = { [weak self] in
          self?.terminationFlushTask = nil
          approveTermination(sender)
          continuation.finish()
        }
        if let writing = self?.writingTools {
          writing.dictation.flushForTermination(complete)
        } else {
          complete()
        }
      }
    }
    return .terminateLater
  }

  func applicationWillTerminate(_ notification: Notification) {
    controlCenterDismissal.stop()
    automatedRunner.stopPreview()
    shortcuts?.stop()
    speechServices?.stop()
    textModels.stop()
    voiceServices?.models.stop()
    controller?.stop()
    cleanupTemporaryPreferences()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

  func applicationDidBecomeActive(_ notification: Notification) {
    AppContentWindowStacking.shared.update(.foreground)
  }

  func applicationDidResignActive(_ notification: Notification) {
    AppContentWindowStacking.shared.update(.background)
  }

  private func cleanupTemporaryPreferences() {
    if let domain = temporaryPreferencesDomain {
      UserDefaults.standard.removePersistentDomain(forName: domain)
      temporaryPreferencesDomain = nil
    }
  }

  private func installStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    item.button?.image = NSImage(
      systemSymbolName: "pawprint.fill", accessibilityDescription: "Sillies")
    item.button?.image?.isTemplate = true
    item.button?.toolTip = String(localized: "Sillies · a little company")
    item.button?.target = self
    item.button?.action = #selector(togglePopover)
    item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    statusItem = item
    popover.behavior = .transient
    popover.animates = true
    popover.delegate = self
  }

  private func controlCenter(_ controller: CompanionController) -> ControlCenterView {
    ControlCenterView(
      controller: controller,
      actions: .init(
        openSettings: { [weak self] in self?.showSettings() },
        openVault: { [weak self] in self?.showVault() },
        openWriting: { [weak self] in
          self?.popover.performClose(nil)
          self?.controller?.onOpenWritingSession?()
        },
        quit: { NSApp.terminate(nil) }),
      speechModels: speechServices?.models, dictation: writingTools?.dictation)
  }

  private func controlCenterHost(
    _ controller: CompanionController, screen: NSScreen?
  ) -> ControlCenterHostingController {
    ControlCenterHostingController(
      content: controlCenter(controller), visibleFrame: CompanionPanel.visibleFrame(for: screen),
      appearance: appearance)
  }

  @objc private func togglePopover() {
    if NSApp.currentEvent?.type == .rightMouseUp {
      showContextMenu()
      return
    }
    guard let button = statusItem?.button else { return }
    if popover.isShown {
      popover.performClose(nil)
    } else {
      let screen = button.window?.screen ?? NSScreen.main
      if popover.contentViewController == nil, let controller {
        popover.contentViewController = controlCenterHost(controller, screen: screen)
      }
      guard let host = popover.contentViewController as? ControlCenterHostingController else {
        return
      }
      host.updateViewport(visibleFrame: CompanionPanel.visibleFrame(for: screen))
      popover.contentSize = host.viewportSize
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
      popover.contentViewController?.view.window?.makeKey()
      controlCenterDismissal.start(popover: popover, statusButton: button)
    }
  }

  func popoverDidClose(_ notification: Notification) { controlCenterDismissal.stop() }

  private func showContextMenu() {
    let menu = NSMenu()
    let pause = NSMenuItem(
      title: controller?.settings.paused == true
        ? String(localized: "Resume companions") : String(localized: "Pause companions"),
      action: #selector(togglePause), keyEquivalent: "p")
    pause.target = self
    menu.addItem(pause)
    let vault = NSMenuItem(
      title: String(localized: "Session Vault…"), action: #selector(openVaultFromMenu),
      keyEquivalent: "v")
    vault.target = self
    menu.addItem(vault)
    let dictate = NSMenuItem(
      title: String(localized: "Start / finish dictation"), action: #selector(toggleDictation),
      keyEquivalent: "")
    dictate.target = self
    menu.addItem(dictate)
    let stash = NSMenuItem(
      title: String(localized: "Search Pocket Stash…"), action: #selector(openStashPicker),
      keyEquivalent: "")
    stash.target = self
    menu.addItem(stash)
    let recovery = NSMenuItem(
      title: String(localized: "Recent writing…"), action: #selector(openWritingHistory),
      keyEquivalent: "")
    recovery.target = self
    menu.addItem(recovery)
    let settings = NSMenuItem(
      title: speechServices?.models.availableUpdateCount ?? 0 > 0
        ? String(localized: "Settings… · Model updates available") : String(localized: "Settings…"),
      action: #selector(showSettings), keyEquivalent: ",")
    settings.target = self
    menu.addItem(settings)
    let checkUpdates = NSMenuItem(
      title: String(localized: "Check for Updates…"), action: #selector(checkForUpdates),
      keyEquivalent: "")
    checkUpdates.target = self
    checkUpdates.isEnabled = Updates.shared.canCheck
    menu.addItem(checkUpdates)
    menu.addItem(.separator())
    let quit = NSMenuItem(
      title: String(localized: "Quit Sillies"), action: #selector(quit), keyEquivalent: "q")
    quit.target = self
    menu.addItem(quit)
    guard let button = statusItem?.button else { return }
    menu.popUp(positioning: nil, at: CGPoint(x: 0, y: button.bounds.minY), in: button)
  }

  @objc private func togglePause() { controller?.commands.perform(.togglePause) }
  @objc private func toggleDictation() { controller?.commands.perform(.toggleDictation) }
  @objc private func openStashPicker() { controller?.commands.perform(.searchStash) }
  @objc private func openWritingHistory() { controller?.commands.perform(.dictationHistory) }
  @objc private func checkForUpdates() { Updates.shared.checkNow() }
  @objc private func quit() { NSApp.terminate(nil) }

  private func openOrCreatePlayground(for controller: CompanionController) -> WindowPlayground {
    popover.performClose(nil)
    let existing = playground ?? WindowPlayground(controller: controller)
    playground = existing
    existing.enableNativeTrackingFixture()
    existing.show()
    return existing
  }

  @objc private func openVaultFromMenu() { controller?.commands.perform(.openVault) }

  private func showVault(recordID: UUID? = nil) {
    if let writingTools {
      Task { [weak self] in
        await writingTools.pasteBack.captureDestination()
        self?.presentVault(recordID: recordID)
      }
    } else {
      presentVault(recordID: recordID)
    }
  }

  private func presentVault(recordID: UUID?) {
    popover.performClose(nil)
    guard let controller else { return }
    let rootView = SessionVaultView(
      vault: controller.skills.vault, initialRecordID: recordID, pasteBack: writingTools?.pasteBack,
      appearance: appearance)
    let host = ThemedHostingController(rootView: rootView, appearance: appearance)
    host.sizingOptions = []
    if let vaultWindow {
      let currentFrame = vaultWindow.frame
      vaultWindow.contentViewController = host
      vaultWindow.setFrame(currentFrame, display: true)
    } else {
      let window = NSWindow(
        contentRect: CGRect(origin: .zero, size: Self.initialVaultWindowSize),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered, defer: false)
      window.title = String(localized: "Sillies · Session Vault")
      AppContentWindowStacking.shared.register(window)
      appearance.register(window)
      window.titlebarAppearsTransparent = true
      window.isReleasedWhenClosed = false
      window.minSize = Self.minVaultWindowSize
      window.contentViewController = host
      window.setContentSize(Self.initialVaultWindowSize)
      window.center()
      vaultWindow = window
    }
    NSApp.activate(ignoringOtherApps: true)
    vaultWindow?.makeKeyAndOrderFront(nil)
  }

  @objc private func showSettings() {
    popover.performClose(nil)
    if settingsWindow == nil, let controller {
      let window = NSWindow(
        contentRect: CGRect(origin: .zero, size: SettingsWindowLayout.initialSize),
        styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered,
        defer: false)
      window.title = String(localized: "Sillies · Settings")
      AppContentWindowStacking.shared.register(window)
      appearance.register(window)
      window.contentMinSize = SettingsWindowLayout.minimumSize
      window.titlebarAppearsTransparent = true
      window.isReleasedWhenClosed = false
      window.contentViewController = ThemedHostingController(
        rootView: SettingsView(
          controller: controller, appearance: appearancePreferences, language: languagePreferences,
          speechModels: speechServices?.models,
          voiceModels: voiceServices?.models, textModels: textModels,
          shortcuts: shortcuts, loginItems: loginItems, writingTools: writingTools,
          navigation: settingsNavigation), appearance: appearance)
      window.center()
      settingsWindow = window
    }
    NSApp.activate(ignoringOtherApps: true)
    settingsWindow?.makeKeyAndOrderFront(nil)
  }

  private func showPreview() {
    guard let controller else { return }
    let host = controlCenterHost(controller, screen: NSScreen.main)
    let size = host.viewportSize
    let window = NSWindow(
      contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled, .closable],
      backing: .buffered, defer: false)
    window.title = String(localized: "Sillies · Control Center")
    AppContentWindowStacking.shared.register(window)
    appearance.register(window)
    window.contentViewController = host
    window.isReleasedWhenClosed = false
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    previewWindow = window
  }

  private func exportPreviews(to directory: URL) {
    guard let controller else { return }
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      if let view = previewWindow?.contentView,
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
      {
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if let data = bitmap.representation(using: .png, properties: [:]) {
          try data.write(to: directory.appendingPathComponent("control-center.png"))
        }
      }
      for character in controller.catalog.characters {
        guard let rig = controller.renderers.make(character.renderer),
          let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Self.exportedCharacterPreviewPixels,
            pixelsHigh: Self.exportedCharacterPreviewPixels,
            bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else { continue }
        let cg = context.cgContext
        cg.scaleBy(
          x: Self.exportedCharacterPreviewScale, y: Self.exportedCharacterPreviewScale)
        rig.root.render(in: cg)
        if let data = bitmap.representation(using: .png, properties: [:]) {
          try data.write(to: directory.appendingPathComponent("\(character.id).png"))
        }
      }
      print("Previews exported to \(directory.path)")
    } catch { fputs("Preview export failed: \(error)\n", stderr) }
  }
}
