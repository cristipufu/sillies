import AppKit
import Observation
import SilliesAudio
import SilliesChat
import SilliesCore
import SilliesReasoning
import SilliesVault
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
  private static let exportedCharacterPreviewPixels = 512
  private static let exportedCharacterPreviewScale: CGFloat = 4

  private var controller: CompanionController?
  private var statusItem: NSStatusItem?
  private let popover = NSPopover()
  private let controlCenterDismissal = ControlCenterDismissal()
  private var settingsWindow: NSWindow?
  private let settingsNavigation = SettingsNavigation()
  private var settingsLifecycle: SettingsWindowLifecycle?
  private var setup: SetupPresentation?
  private var setupSuggestions: SetupModelSuggestions?
  private var companionPreferences: CompanionPreferences?
  private var speechServices: SpeechServices?
  private var voiceServices: VoiceServices?
  private var appearancePreferences: AppearancePreferences?
  private var languagePreferences: LanguagePreferences?
  private let appearance = ThemeEnvironment()
  private var diagnostics: DiagnosticServices?
  private let diagnosticsExport = DiagnosticsExportController()
  private lazy var chatWindow = ChatSessionWindowController(
    appearance: appearance, reading: ChatReadingPreferences(defaults: .standard))
  private lazy var reasoningServices = ReasoningServices(
    diagnostics: diagnostics?.sink ?? .disabled)
  private lazy var textModels = TextModelsPresentation(environment: reasoningServices.models)
  private var shortcuts: CommandShortcuts?
  private var writingTools: WritingTools?
  private let loginItems = LoginItemSettings()
  private lazy var audioSessionWindow = AudioSessionWindowController(appearance: appearance) {
    [weak self] in
    guard let self else { return }
    self.settingsNavigation.returnsToSetup = false
    self.settingsNavigation.destination = .intelligence
    self.showSettings()
  }
  private var vaultController: SessionVaultWindowController?
  private var vaultWindow: NSWindow? { vaultController?.window }
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
      if !launch.isAutomatedRun {
        let diagnostics = DiagnosticServices()
        self.diagnostics = diagnostics
        diagnostics.start()
      }
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
        if let setup, !setup.journey.introduced {
          setup.journey.deferSetup()
          settingsNavigation.destination = .setup
          showSettings()
        }
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
      diagnostics?.sink.record(.init(.app, .failed).failing(error))
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
      Task {
        [
          models = reasoningServices.models, voices = voiceServices?.environment,
          search = searchServices?.environment
        ] in
        await models.setActivity(active ? .active : .suspended)
        if active {
          await voices?.resume()
          await search?.resume()
        } else {
          await voices?.stop()
          await search?.stop()
        }
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

  private var conversationSessions: ConversationSessions?
  private var conversations: ConversationLibrary?
  private var searchServices: SearchServices?

  private func configureChat(
    skills: SkillCoordinator, speech: SpeechServices, characters: [CharacterDefinition]
  ) throws {
    let reference = VoicePlaybackReference()
    let voices = try VoiceServices(
      renderReference: reference.append, diagnostics: diagnostics?.sink ?? .disabled)
    voiceServices = voices
    let preferences = CompanionPreferences(defaults: .standard, characters: characters)
    companionPreferences = preferences
    let conversations = ConversationLibrary(directory: skills.vault.storageDirectory)
    self.conversations = conversations
    searchServices = SearchServices(conversations: conversations, vault: skills.vault.library)
    let composition = ConversationComposition(
      dependencies: .init(
        speech: speech, voices: voices, reasoning: reasoningServices, conversations: conversations,
        vault: skills.vault.library, preferences: preferences,
        diagnostics: diagnostics?.sink ?? .disabled),
      reference: reference)
    let sessions = ConversationSessions(
      profile: { id in characters.first { $0.id == id }.flatMap { preferences.profile(for: $0) } },
      services: { composition.services(for: $0.id) },
      languageOverride: { preferences.customization(for: $0).language })
    conversationSessions = sessions
    preferences.onChange = { [weak sessions] id in sessions?.refreshProfile(for: id) }
    configureSetup(characters: characters, composition: composition, preferences: preferences)
    controller?.onConversationAnchorChanged = { [weak self] in self?.chatWindow.follow($0) }
    skills.makeChatSession = { id, name in sessions.session(for: .init(id: id, name: name)) }
    skills.onCloseChatSession = { [weak self] session in self?.chatWindow.close(session) }
    skills.onOpenChatSettings = { [weak self] destination in
      guard let self, let setup = self.setup else { return }
      if let session = self.controller?.skills.activeChatSession {
        setup.chooseCompanion(session.companionID)
        setup.chooseActivity(session.mode == .talk ? .talk : .chat)
      }
      self.settingsNavigation.showConversationSettings(destination, setup: setup)
      self.showSettings()
    }
    skills.onOpenChatSession = { [weak self, weak skills] session in
      guard let self, let skills else { return }
      self.chatWindow.show(
        session,
        openSettings: { [weak skills] in skills?.onOpenChatSettings?($0) },
        renderer: characters.first(where: { $0.id == session.companionID })?.renderer,
        vault: .init(
          store: skills.vault, openRecord: { [weak self] in self?.showVault(recordID: $0) }),
        anchor: self.controller?.conversationAnchor(for: session.companionID))
    }
  }

  private func configureSetup(
    characters: [CharacterDefinition], composition: ConversationComposition,
    preferences: CompanionPreferences
  ) {
    guard let speech = speechServices, let voices = voiceServices else { return }
    setupSuggestions = SetupModelSuggestions(
      text: textModels, voice: voices.models, speech: speech.models)
    setup = SetupPresentation(
      journey: SetupJourney(defaults: .standard, availableIDs: characters.map(\.id)),
      profiles: preferences, characters: characters,
      audio: SetupAudioPreview(isBusy: { [weak self] in
        self?.controller?.skills.hasActiveCaptureSkill == true
          || self?.controller?.skills.canStartAudio() == false
      }),
      actions: .init(
        services: { composition.services(for: $0) },
        isGranted: SetupPermissions.isGranted, requestPermission: SetupPermissions.request,
        meetingLanguage: {
          let environment = speech.languages
          let catalog = try await environment.load()
          return catalog.preferredLanguage(
            savedIdentifier: environment.preferences.selectedIdentifier(for: catalog.model))?.id
        },
        openSettings: { [weak self] destination in
          self?.settingsNavigation.returnsToSetup = true
          self?.settingsNavigation.destination = destination
          self?.showSettings()
        },
        launch: { [weak self] character, activity in
          self?.launchSetup(character, activity: activity)
        },
        dismiss: { [weak self] in self?.settingsWindow?.close() }))
    controller?.skills.isAudioReserved = { [weak setup] in
      guard let setup else { return false }
      return setup.audio.phase != .idle
    }
  }

  private func launchSetup(_ character: CharacterDefinition, activity: SetupActivity)
    -> SessionFailure?
  {
    guard let controller else {
      return .init(
        category: .captureUnavailable,
        message: String(
          localized: "This companion could not open a conversation. Please try again."))
    }
    controller.settings.enabledCharacters.insert(character.id)
    controller.settings.paused = false
    if activity == .chat || activity == .talk {
      if let failure = controller.skills.startConversation(
        activity == .talk ? .talk : .chat, for: character.id, name: character.name)
      {
        return failure
      }
    } else {
      controller.greet()
    }
    settingsWindow?.close()
    return nil
  }

  private func openConversation(_ mode: ConversationMode, companionID: String) {
    popover.performClose(nil)
    setup?.chooseCompanion(companionID)
    setup?.openConversation(mode)
  }

  private func makeSkillCoordinator(for launch: LaunchConfiguration) throws -> SkillCoordinator {
    guard launch.isAutomatedRun else {
      let speech = try SpeechServices(diagnostics: diagnostics?.sink ?? .disabled)
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
      if let diagnostics {
        isTerminating = true
        let approve = onTerminationApproved
        diagnostics.shutdown { approve(sender) }
        return .terminateLater
      }
      return .terminateNow
    }
    isTerminating = true
    setup?.stop()
    vaultController?.close()
    diagnosticsExport.cancel()
    controlCenterDismissal.stop()
    shortcuts?.stop()
    automatedRunner.stopPreview()
    speechServices?.stop()
    textModels.stop()
    searchServices?.models.stop()
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
          if let self, let failed = self.conversationSessions?.failedSave {
            self.isTerminating = false
            self.controller?.start()
            self.observeModelUpdateActivity()
            self.observeCommandAvailability()
            sender.reply(toApplicationShouldTerminate: false)
            self.controller?.skills.startConversation(
              .chat, for: failed.companionID, name: failed.companionName)
          } else {
            let finishDiagnostics: @MainActor @Sendable () -> Void = { [weak self] in
              if let diagnostics = self?.diagnostics {
                diagnostics.shutdown { approveTermination(sender) }
              } else {
                approveTermination(sender)
              }
            }
            if let setup = self?.setup {
              setup.audio.finish(finishDiagnostics)
            } else {
              finishDiagnostics()
            }
          }
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
    setup?.stop()
    vaultController?.close()
    diagnosticsExport.cancel()
    controlCenterDismissal.stop()
    automatedRunner.stopPreview()
    shortcuts?.stop()
    speechServices?.stop()
    textModels.stop()
    searchServices?.models.stop()
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
        openStash: { [weak self] in self?.showVault(.stash) },
        openCompanions: { [weak self] in
          self?.settingsNavigation.destination = .companions
          self?.settingsNavigation.companionsPage = .crew
          self?.showSettings()
        },
        openWriting: { [weak self] in
          self?.popover.performClose(nil)
          self?.controller?.onOpenWritingSession?()
        },
        openConversation: { [weak self] in self?.openConversation($0, companionID: $1) },
        openSetup: { [weak self] in
          self?.settingsNavigation.destination = .setup
          self?.showSettings()
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
    showVault(recordID.map { .record($0) } ?? .resume)
  }

  private func showVault(_ destination: SessionVaultWindowController.Destination) {
    if let writingTools {
      Task { [weak self] in
        await writingTools.pasteBack.captureDestination()
        self?.presentVault(destination)
      }
    } else {
      presentVault(destination)
    }
  }

  private func presentVault(_ destination: SessionVaultWindowController.Destination) {
    popover.performClose(nil)
    guard let controller else { return }
    if vaultController == nil {
      vaultController = SessionVaultWindowController(
        vault: controller.skills.vault, appearance: appearance,
        services: .init(
          pasteBack: writingTools?.pasteBack,
          conversations: conversations.map { library in
            .init(
              repository: library,
              open: { [weak self] owner, messageID in
                guard let self else { return Self.conversationUnavailable }
                return self.openVaultConversation(owner, messageID: messageID)
              })
          },
          discussion: .init(
            availableCompanions: { [weak controller] in
              guard let controller else { return [] }
              return controller.catalog.characters.filter {
                $0.chat != nil && controller.settings.enabledCharacters.contains($0.id)
              }.map { .init(id: $0.id, name: $0.name) }
            },
            open: { [weak self] id, owner in
              guard let self, let skills = self.controller?.skills else {
                return Self.conversationUnavailable
              }
              let failure = skills.startConversation(
                .chat, for: owner.id, name: owner.name, selectedRecord: id)
              if failure == nil { self.vaultController?.hide() }
              return failure
            })))
    }
    vaultController?.show(destination)
  }

  private static var conversationUnavailable: SessionFailure {
    .init(
      category: .captureUnavailable,
      message: String(localized: "This companion could not open a conversation. Please try again."))
  }

  private func openVaultConversation(_ owner: ConversationOwner, messageID: UUID?)
    -> SessionFailure?
  {
    guard let skills = controller?.skills else { return Self.conversationUnavailable }
    let failure = skills.openConversation(for: owner) { [weak self] session in
      if let messageID { self?.chatWindow.showMessage(messageID, in: session) }
    }
    if failure == nil { vaultController?.hide() }
    return failure
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
      let lifecycle = SettingsWindowLifecycle(
        stop: { [weak self] in
          self?.setup?.stop()
          self?.diagnosticsExport.cancel()
        },
        refresh: { [weak self] in
          if self?.settingsNavigation.destination == .setup { self?.setup?.refresh() }
        })
      settingsLifecycle = lifecycle
      window.delegate = lifecycle
      window.contentViewController = ThemedHostingController(
        rootView: SettingsView(
          controller: controller, appearance: appearancePreferences, language: languagePreferences,
          speechModels: speechServices?.models,
          voiceModels: voiceServices?.models, textModels: textModels,
          searchModels: searchServices?.models,
          shortcuts: shortcuts, loginItems: loginItems, writingTools: writingTools,
          diagnostics: diagnostics?.presentation,
          setup: setup, suggestions: setupSuggestions, companionPreferences: companionPreferences,
          exportDiagnostics: { [weak self] in
            guard let self, let model = self.diagnostics?.presentation,
              let parent = self.settingsWindow
            else { return }
            self.diagnosticsExport.chooseFile(for: model, parent: parent)
          },
          actions: .init(
            openRetention: { [weak self] in self?.presentVault(.retention) },
            openMemories: { [weak self] id in
              guard let self, let controller = self.controller,
                let character = controller.catalog.characters.first(where: { $0.id == id })
              else { return Self.conversationUnavailable }
              return controller.skills.openConversation(for: .init(id: id, name: character.name)) {
                [weak self] _ in
                self?.chatWindow.navigation.show(.memories)
                self?.settingsWindow?.close()
              }
            }),
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
