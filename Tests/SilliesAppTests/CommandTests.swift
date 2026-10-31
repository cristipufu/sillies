import AppKit
import Carbon
import SilliesCore
import Testing

@testable import SilliesApp

@Test @MainActor func suspendedShortcutsStayRegisteredAndStopReleasesThem() throws {
  let domain = "sillies-shortcut-lifecycle-\(UUID())"
  let defaults = try #require(UserDefaults(suiteName: domain))
  defer { defaults.removePersistentDomain(forName: domain) }
  let hotkeys = GlobalHotkeys()
  let shortcuts = CommandShortcuts(defaults: defaults, hotkeys: hotkeys)
  shortcuts.assign(nil, to: .holdDictation)
  shortcuts.assign(nil, to: .toggleDictation)
  shortcuts.assign(
    .init(keyCode: UInt32(kVK_F18), modifiers: [.control, .option, .command], keyLabel: "F18"),
    to: .toggleDictation)
  shortcuts.start()
  defer { shortcuts.stop() }
  #expect(shortcuts.errors.isEmpty)
  #expect(hotkeys.registeredCommands == [.toggleDictation])
  for _ in 0..<100 {
    shortcuts.configure(.suspended)
    #expect(hotkeys.registeredCommands == [.toggleDictation])
    shortcuts.configure(.active)
    #expect(hotkeys.registeredCommands == [.toggleDictation])
  }
  shortcuts.stop()
  #expect(hotkeys.registeredCommands.isEmpty)
}

@Test func everyShortcutHasOneDiscoverableGroupAndAnExplanation() {
  let commands = CommandShortcutGroup.allCases.flatMap(\.commands)
  #expect(Set(commands) == Set(AppCommand.allCases))
  #expect(commands.count == AppCommand.allCases.count)
  #expect(commands.allSatisfy { !$0.shortcutExplanation.isEmpty })
}

@Test @MainActor func commandShortcutsRejectCollisionsAndPreserveSavedBindings() throws {
  let domain = "sillies-shortcuts-\(UUID())"
  let defaults = try #require(UserDefaults(suiteName: domain))
  defer { defaults.removePersistentDomain(forName: domain) }
  let preferences = CommandShortcuts(defaults: defaults)
  let shortcut = CommandShortcut(keyCode: 9, modifiers: [.control, .option], keyLabel: "V")
  preferences.assign(shortcut, to: .openVault)
  preferences.assign(shortcut, to: .snap)
  #expect(preferences.bindings[AppCommand.snap.rawValue] == nil)
  #expect(preferences.errors[AppCommand.snap.rawValue]?.contains("Open Vault") == true)
  preferences.assign(.init(keyCode: 9, modifiers: [], keyLabel: "V"), to: .openVault)
  #expect(preferences.bindings[AppCommand.openVault.rawValue] == shortcut)
  let restored = CommandShortcuts(defaults: defaults)
  #expect(restored.bindings[AppCommand.openVault.rawValue] == shortcut)
  restored.assign(nil, to: .openVault)
  #expect(CommandShortcuts(defaults: defaults).bindings[AppCommand.openVault.rawValue] == nil)
}

private actor FixtureLoginService: LoginItemServicing {
  var current = LoginItemStatus.disabled
  func status() -> LoginItemStatus { current }
  func update(_ preference: LoginItemPreference) -> LoginItemStatus {
    current = preference == .enabled ? .requiresApproval : .disabled
    return current
  }
}

@Test @MainActor func loginSettingsReflectSystemApprovalInsteadOfAssumingSuccess() async {
  let settings = LoginItemSettings(service: FixtureLoginService())
  await settings.update(.enabled)
  #expect(settings.requested)
  #expect(settings.status == .requiresApproval)
  #expect(!settings.isUpdating)
  await settings.update(.disabled)
  #expect(!settings.requested)
}

@Test @MainActor func commandsDiscardTargetsAfterFocusChangesOrCancellation() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  let skills = SkillCoordinator(vault: vault)
  let app = FrontmostApplication(processID: 123, name: "Fixture", bundleIdentifier: "test.app")
  let target = WindowTargetCandidate(
    windowID: 5, processID: 123, appName: "Fixture",
    frame: CGRect(x: 50, y: 50, width: 600, height: 400))
  var focused: FrontmostApplication? = app
  var completion: CheckedContinuation<WindowTargetCandidate?, Never>?
  var openedVault = 0
  var paused = false
  let dispatcher = CommandDispatcher(
    skills: skills,
    environment: .init(
      isAvailable: { !paused },
      companion: { .init(id: "mochi", name: "Mochi", position: .zero) },
      openVault: { openedVault += 1 }, togglePause: { paused.toggle() }, saveClipboard: { _ in }),
    targeting: .init(
      current: { focused },
      resolve: { _, _ in
        await withCheckedContinuation { completion = $0 }
      }))
  defer { dispatcher.stop() }
  dispatcher.perform(.snap)
  while completion == nil { await Task.yield() }
  focused = nil
  completion?.resume(returning: target)
  completion = nil
  await Task.yield()
  #expect(!skills.binding(for: "mochi").isBound)
  focused = app
  dispatcher.perform(.snap)
  while completion == nil { await Task.yield() }
  dispatcher.cancelPending()
  completion?.resume(returning: target)
  await Task.yield()
  #expect(!skills.binding(for: "mochi").isBound)
  dispatcher.perform(.togglePause)
  dispatcher.perform(.openVault)
  #expect(paused && openedVault == 1)
  await skills.shutdown()
}
