import AppKit
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

private struct LaunchConfiguration {
  let arguments: [String]

  init(arguments: [String] = ProcessInfo.processInfo.arguments) {
    self.arguments = arguments
  }

  var runsInputFixture: Bool { arguments.contains("--input-fixture") }
  var usesDarkAppearance: Bool { arguments.contains("--dark") }
  var usesAccessibility: Bool { !arguments.contains("--without-accessibility") }
  var validatesCatalogOnly: Bool { arguments.contains("--validate-catalog") }
  var showsPreview: Bool {
    arguments.contains("--preview") || arguments.contains("--snapshot-dir")
  }
  var isAutomatedRun: Bool {
    arguments.contains("--smoke-test") || arguments.contains("--snapshot-dir")
      || arguments.contains("--performance-check") || arguments.contains("--window-test")
      || arguments.contains("--external-drag-test")
      || arguments.contains("--drag-latency-test")
      || arguments.contains("--presentation-test")
      || arguments.contains("--interaction-test")
      || arguments.contains("--drop-return-test")
      || arguments.contains("--companion-drag-test")
  }

  func optionValue(after flag: String) -> String? {
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
      return nil
    }
    return arguments[index + 1]
  }

  @MainActor
  func apply(to settings: AppSettings) {
    if isAutomatedRun { settings.followsWindows = false }
    if arguments.contains("--window-test") { settings.followsWindows = true }
    if arguments.contains("--drag-latency-test")
      || arguments.contains("--external-drag-test")
      || arguments.contains("--interaction-test")
    {
      settings.followsWindows = true
      settings.reduceMotion = true
    }
    if arguments.contains("--performance-check") {
      settings.followsWindows = true
      settings.activity = .calm
    }
    if arguments.contains("--drop-return-test") || arguments.contains("--companion-drag-test") {
      settings.followsWindows = true
      settings.reduceMotion = false
      settings.activity = .calm
    }
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
  private var controller: CompanionController?
  private var statusItem: NSStatusItem?
  private let popover = NSPopover()
  private var settingsWindow: NSWindow?
  private var vaultWindow: NSWindow?
  private var previewWindow: NSWindow?
  private var temporaryPreferencesDomain: String?
  private var playground: WindowPlayground?
  private var inputFixture: InputWindowFixture?
  private var externalDragCheck: ExternalDragCheck?
  private var playInteractionCheck: PlayInteractionCheck?
  private var companionDragCheck: CompanionDragResponseCheck?
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
      if launch.runsInputFixture {
        inputFixture = InputWindowFixture()
        inputFixture?.start()
        return
      }
      if launch.usesDarkAppearance { NSApp.appearance = NSAppearance(named: .darkAqua) }
      let settings = makeSettings(for: launch)
      let skills: SkillCoordinator
      if launch.isAutomatedRun {
        let tempVault = FileManager.default.temporaryDirectory
          .appendingPathComponent("sillies-vault-\(UUID().uuidString)", isDirectory: true)
        skills = SkillCoordinator(vault: SessionVaultStore(directory: tempVault))
      } else {
        skills = SkillCoordinator()
      }
      let controller = try CompanionController(
        settings: settings, useAccessibility: launch.usesAccessibility, skills: skills)
      controller.onOpenVault = { [weak self] recordID in
        self?.showVault(recordID: recordID)
      }
      self.controller = controller
      if launch.validatesCatalogOnly {
        print(
          "Validated \(controller.catalog.characters.count) character packs and all animation references."
        )
        NSApp.terminate(nil)
        return
      }
      if launch.isAutomatedRun {
        settings.enabledCharacters = Set(controller.catalog.characters.map(\.id))
      }
      controller.start()
      if !launch.isAutomatedRun {
        _ = Updates.shared
        installStatusItem()
      }
      if launch.showsPreview { showPreview() }
      runLaunchAction(launch, controller: controller)
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

  private func runLaunchAction(_ launch: LaunchConfiguration, controller: CompanionController) {
    let args = launch.arguments
    if let snapshotPath = launch.optionValue(after: "--snapshot-dir") {
      let directory = URL(fileURLWithPath: snapshotPath, isDirectory: true)
      DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
        self?.exportPreviews(to: directory)
        NSApp.terminate(nil)
      }
    } else if args.contains("--smoke-test") {
      RuntimeChecks.smokeTest(controller)
    } else if args.contains("--presentation-test") {
      RuntimeChecks.presentationTest()
    } else if args.contains("--interaction-test") || args.contains("--drop-return-test") {
      let previous = NSWorkspace.shared.frontmostApplication
      showPlayground()
      if let playground {
        playInteractionCheck = PlayInteractionCheck(
          controller: controller, playground: playground, previousApplication: previous,
          mode: args.contains("--drop-return-test") ? .dropReturn : .interaction)
        playInteractionCheck?.start()
      }
    } else if args.contains("--companion-drag-test") {
      guard let target = launch.optionValue(after: "--target-bundle") else {
        fputs("--companion-drag-test requires --target-bundle\n", stderr)
        NSApp.terminate(nil)
        return
      }
      companionDragCheck = CompanionDragResponseCheck(controller: controller, targetBundle: target)
      companionDragCheck?.start()
    } else if args.contains("--performance-check") {
      showPlayground()
      RuntimeChecks.performanceCheck(controller)
    } else if args.contains("--window-test") {
      showPlayground()
      if let playground { RuntimeChecks.windowTest(controller, playground: playground) }
    } else if args.contains("--drag-latency-test") {
      showPlayground()
      if let playground {
        DragLatencyCheck(
          controller: controller, playground: playground, allowLag: args.contains("--allow-lag")
        ).start()
      }
    } else if args.contains("--external-drag-test") {
      let targetBundle = launch.optionValue(after: "--target-bundle")
      let fraction = launch.optionValue(after: "--target-header-fraction").flatMap(Double.init)
      externalDragCheck = ExternalDragCheck(
        controller: controller, targetBundle: targetBundle, targetHeaderFraction: fraction,
        expectsStationary: args.contains("--expect-stationary"))
      externalDragCheck?.start()
    } else if args.contains("--playground") {
      showPlayground()
    }
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard !isTerminating else { return .terminateLater }
    guard let controller else {
      cleanupTemporaryPreferences()
      return .terminateNow
    }
    isTerminating = true
    controller.stop()
    controller.skills.vault.cancelPendingSummaries()
    cleanupTemporaryPreferences()
    let vault = controller.skills.vault
    let approveTermination = onTerminationApproved
    terminationFlushTask = Task { @MainActor [weak self] in
      await vault.flush()
      self?.terminationFlushTask = nil
      approveTermination(sender)
    }
    return .terminateLater
  }

  func applicationWillTerminate(_ notification: Notification) {
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
      quit: { NSApp.terminate(nil) })
  }

  private func controlCenterHost(
    _ controller: CompanionController, screen: NSScreen?
  ) -> NSViewController {
    let content = controlCenter(controller)
    let idealHeight = NSHostingView(rootView: content).fittingSize.height
    let compactHeight: CGFloat = 640
    let availableHeight = min(
      compactHeight, max(240, (screen?.visibleFrame.height ?? idealHeight) - 24))
    return NSHostingController(
      rootView: ScrollView(.vertical) {
        content
      }
      .scrollBounceBehavior(.basedOnSize)
      .frame(width: 388, height: min(idealHeight, availableHeight))
      .background(SilliesTheme.paper))
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
      if popover.contentViewController == nil, let controller {
        popover.contentViewController = controlCenterHost(
          controller, screen: button.window?.screen ?? NSScreen.main)
      }
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
      title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
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

  @objc private func togglePause() { controller?.settings.paused.toggle() }
  @objc private func checkForUpdates() { Updates.shared.checkNow() }
  @objc private func quit() { NSApp.terminate(nil) }

  private func showPlayground() {
    popover.performClose(nil)
    guard let controller else { return }
    if playground == nil { playground = WindowPlayground(controller: controller) }
    playground?.show()
  }

  @objc private func openVaultFromMenu() { showVault() }

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
      let initialSize = NSSize(width: 980, height: 660)
      let window = NSWindow(
        contentRect: CGRect(origin: .zero, size: initialSize),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered, defer: false)
      window.title = "Sillies · Session Vault"
      window.titlebarAppearsTransparent = true
      window.isReleasedWhenClosed = false
      window.minSize = NSSize(width: 880, height: 560)
      window.contentViewController = host
      window.setContentSize(initialSize)
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
        contentRect: CGRect(x: 0, y: 0, width: 560, height: 690),
        styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
      window.title = "Sillies Settings"
      window.titlebarAppearsTransparent = true
      window.isReleasedWhenClosed = false
      window.contentViewController = NSHostingController(
        rootView: SettingsView(controller: controller))
      window.center()
      settingsWindow = window
    }
    NSApp.activate(ignoringOtherApps: true)
    settingsWindow?.makeKeyAndOrderFront(nil)
  }

  private func showPreview() {
    guard let controller else { return }
    let host = controlCenterHost(controller, screen: NSScreen.main)
    let size = host.view.fittingSize
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
            bitmapDataPlanes: nil, pixelsWide: 512, pixelsHigh: 512, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else { continue }
        let cg = context.cgContext
        cg.scaleBy(x: 4, y: 4)
        rig.root.render(in: cg)
        if let data = bitmap.representation(using: .png, properties: [:]) {
          try data.write(to: directory.appendingPathComponent("\(character.id).png"))
        }
      }
      print("Previews exported to \(directory.path)")
    } catch { fputs("Preview export failed: \(error)\n", stderr) }
  }
}
