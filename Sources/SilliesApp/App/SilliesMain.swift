import AppKit
import Observation
import SwiftUI

@main
struct SilliesMain {
  @MainActor
  static func main() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
  private static let initialVaultWindowSize = NSSize(width: 980, height: 660)
  private static let minVaultWindowSize = NSSize(width: 880, height: 560)
  private static let settingsWindowSize = NSSize(width: 560, height: 690)
  private static let exportedCharacterPreviewPixels = 512
  private static let exportedCharacterPreviewScale: CGFloat = 4

  private var controller: CompanionController?
  private var statusItem: NSStatusItem?
  private let popover = NSPopover()
  private var settingsWindow: NSWindow?
  private var speechServices: SpeechServices?
  private var shortcuts: CommandShortcuts?
  private let loginItems = LoginItemSettings()
  private let audioSessionWindow = AudioSessionWindowController()
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
      if launch.runsInputFixture {
        automatedRunner.startInputFixture()
        return
      }
      if launch.usesDarkAppearance { NSApp.appearance = NSAppearance(named: .darkAqua) }
      let settings = makeSettings(for: launch)
      let skills = makeSkillCoordinator(for: launch)
      let controller = try CompanionController(
        settings: settings,
        services: .init(
          accessibility: launch.usesAccessibility ? .enabled : .disabled, skills: skills))
      controller.onOpenVault = { [weak self] recordID in
        self?.showVault(recordID: recordID)
      }
      skills.onOpenAudioSession = { [weak self] in self?.audioSessionWindow.show($0) }
      self.controller = controller
      if launch.validatesCatalogOnly {
        automatedRunner.validateCatalog(characterCount: controller.catalog.characters.count)
        return
      }
      if launch.isAutomatedRun {
        settings.enabledCharacters = Set(controller.catalog.characters.map(\.id))
      }
      controller.start()
      speechServices?.start()
      observeModelUpdateActivity()
      if !launch.isAutomatedRun {
        let shortcuts = CommandShortcuts()
        shortcuts.onEvent = { [weak controller] command, edge in
          if edge == .pressed { controller?.commands.perform(command) }
        }
        self.shortcuts = shortcuts
        shortcuts.start()
        observeCommandAvailability()
        _ = Updates.shared
        installStatusItem()
      }
      if launch.showsPreview { showPreview() }
      automatedRunner.run(
        launch,
        controller: controller,
        openPlayground: { [unowned self] in self.openOrCreatePlayground(for: controller) },
        exportPreviews: { [weak self] directory in self?.exportPreviews(to: directory) })
    } catch {
      let alert = NSAlert()
      alert.messageText = "Sillies couldn’t get settled."
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
    launch.apply(to: settings)
    return settings
  }

  private func observeModelUpdateActivity() {
    guard !isTerminating, let controller, let updates = speechServices?.models.updates else {
      return
    }
    withObservationTracking {
      updates.setActivity(controller.shouldRun && controller.liveCount > 0 ? .active : .suspended)
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

  private func makeSkillCoordinator(for launch: LaunchConfiguration) -> SkillCoordinator {
    guard launch.isAutomatedRun else {
      let speech = SpeechServices()
      speechServices = speech
      return SkillCoordinator(audioFactory: speech.captureFactory, audioLanguages: speech.languages)
    }
    let tempVault = FileManager.default.temporaryDirectory
      .appendingPathComponent("sillies-vault-\(UUID().uuidString)", isDirectory: true)
    return SkillCoordinator(vault: SessionVaultStore(directory: tempVault))
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard !isTerminating else { return .terminateNow }
    guard let controller else {
      cleanupTemporaryPreferences()
      return .terminateNow
    }
    isTerminating = true
    shortcuts?.stop()
    automatedRunner.stopPreview()
    speechServices?.stop()
    cleanupTemporaryPreferences()
    let approveTermination = onTerminationApproved
    let (stream, continuation) = AsyncStream<Void>.makeStream()
    terminationFlushTask = Task {
      for await _ in stream { break }
    }
    controller.flushForTermination { [weak self, weak controller] in
      MainActor.assumeIsolated {
        controller?.drainPreviewsForTermination()
        self?.terminationFlushTask = nil
        approveTermination(sender)
        continuation.finish()
      }
    }
    return .terminateLater
  }

  func applicationWillTerminate(_ notification: Notification) {
    shortcuts?.stop()
    speechServices?.stop()
    controller?.stop()
    cleanupTemporaryPreferences()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

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
    item.button?.toolTip = "Sillies · a little company"
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
      controller: controller, openSettings: { [weak self] in self?.showSettings() },
      openPlayground: { [weak self] in self?.showPlayground() },
      openVault: { [weak self] in self?.showVault() },
      quit: { NSApp.terminate(nil) }, speechModels: speechServices?.models)
  }

  private func controlCenterHost(
    _ controller: CompanionController, screen: NSScreen?
  ) -> ControlCenterHostingController {
    ControlCenterHostingController(
      content: controlCenter(controller), visibleFrame: CompanionPanel.visibleFrame(for: screen))
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
    }
  }

  private func showContextMenu() {
    let menu = NSMenu()
    let pause = NSMenuItem(
      title: controller?.settings.paused == true ? "Resume companions" : "Pause companions",
      action: #selector(togglePause), keyEquivalent: "p")
    pause.target = self
    menu.addItem(pause)
    let vault = NSMenuItem(
      title: "Session Vault…", action: #selector(openVaultFromMenu), keyEquivalent: "v")
    vault.target = self
    menu.addItem(vault)
    let settings = NSMenuItem(
      title: speechServices?.models.availableUpdateCount ?? 0 > 0
        ? "Settings… · Model updates available" : "Settings…",
      action: #selector(showSettings), keyEquivalent: ",")
    settings.target = self
    menu.addItem(settings)
    let checkUpdates = NSMenuItem(
      title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
    checkUpdates.target = self
    checkUpdates.isEnabled = Updates.shared.canCheck
    menu.addItem(checkUpdates)
    menu.addItem(.separator())
    let quit = NSMenuItem(title: "Quit Sillies", action: #selector(quit), keyEquivalent: "q")
    quit.target = self
    menu.addItem(quit)
    guard let button = statusItem?.button else { return }
    menu.popUp(positioning: nil, at: CGPoint(x: 0, y: button.bounds.minY), in: button)
  }

  @objc private func togglePause() { controller?.commands.perform(.togglePause) }
  @objc private func checkForUpdates() { Updates.shared.checkNow() }
  @objc private func quit() { NSApp.terminate(nil) }

  private func showPlayground() {
    guard let controller else { return }
    _ = openOrCreatePlayground(for: controller)
  }

  private func openOrCreatePlayground(for controller: CompanionController) -> WindowPlayground {
    popover.performClose(nil)
    let existing = playground ?? WindowPlayground(controller: controller)
    playground = existing
    existing.show()
    return existing
  }

  @objc private func openVaultFromMenu() { controller?.commands.perform(.openVault) }

  private func showVault(recordID: UUID? = nil) {
    popover.performClose(nil)
    guard let controller else { return }
    let rootView = SessionVaultView(
      vault: controller.skills.vault, initialRecordID: recordID)
    let host = NSHostingController(rootView: rootView)
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
      window.title = "Sillies · Session Vault"
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
        contentRect: CGRect(origin: .zero, size: Self.settingsWindowSize),
        styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
      window.title = "Sillies Settings"
      window.titlebarAppearsTransparent = true
      window.isReleasedWhenClosed = false
      window.contentViewController = NSHostingController(
        rootView: SettingsView(
          controller: controller, speechModels: speechServices?.models,
          shortcuts: shortcuts, loginItems: loginItems))
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
    window.title = "Sillies · Control Center"
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
