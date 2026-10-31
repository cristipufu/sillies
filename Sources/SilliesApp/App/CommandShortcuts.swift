import Carbon
import Foundation
import Observation
import SilliesCore

@MainActor @Observable
final class CommandShortcuts {
  enum Availability { case active, suspended }
  private static let preferenceKey = "commandShortcuts.v1"
  private(set) var bindings: [String: CommandShortcut] = [:]
  private(set) var errors: [String: String] = [:]
  private let defaults: UserDefaults
  @ObservationIgnored private let hotkeys: GlobalHotkeys
  @ObservationIgnored private var running = false
  @ObservationIgnored private var availability = Availability.active
  @ObservationIgnored var onEvent: ((AppCommand, GlobalHotkeys.Edge) -> Void)?

  init(defaults: UserDefaults = .standard, hotkeys: GlobalHotkeys = GlobalHotkeys()) {
    self.defaults = defaults
    self.hotkeys = hotkeys
    if let data = defaults.data(forKey: Self.preferenceKey) {
      do { bindings = try JSONDecoder().decode([String: CommandShortcut].self, from: data) } catch {
        fputs("Could not load keyboard shortcuts: \(error)\n", stderr)
      }
    } else {
      bindings = [
        AppCommand.holdDictation.rawValue: .init(
          keyCode: UInt32(kVK_Space), modifiers: [.control, .option], keyLabel: "Space"),
        AppCommand.toggleDictation.rawValue: .init(
          keyCode: UInt32(kVK_ANSI_D), modifiers: [.control, .option], keyLabel: "D"),
      ]
    }
  }

  func start() {
    guard !running else { return }
    running = true
    hotkeys.onEvent = { [weak self] command, edge in self?.onEvent?(command, edge) }
    for command in AppCommand.allCases {
      if isAvailable(command), let shortcut = bindings[command.rawValue] {
        install(shortcut, for: command)
      }
    }
  }

  func configure(_ availability: Availability) {
    guard self.availability != availability else { return }
    self.availability = availability
    guard running else { return }
    stop()
    start()
  }

  private func isAvailable(_ command: AppCommand) -> Bool {
    availability == .active || command == .togglePause || command == .openVault
      || command == .dictationHistory
  }

  func stop() {
    running = false
    hotkeys.stop()
    hotkeys.onEvent = nil
  }

  func assign(_ shortcut: CommandShortcut?, to command: AppCommand) {
    if let shortcut {
      guard shortcut.isValid else {
        errors[command.rawValue] = "Include Command, Option, or Control."
        return
      }
      if let conflict = AppCommand.allCases.first(where: {
        $0 != command && bindings[$0.rawValue]?.conflicts(with: shortcut) == true
      }) {
        errors[command.rawValue] = "Already used by \(conflict.title)."
        return
      }
      if bindings[command.rawValue] == shortcut { return }
      if running, isAvailable(command), !install(shortcut, for: command) { return }
    } else {
      hotkeys.unregister(command)
    }
    bindings[command.rawValue] = shortcut
    errors[command.rawValue] = nil
    do { defaults.set(try JSONEncoder().encode(bindings), forKey: Self.preferenceKey) } catch {
      errors[command.rawValue] = "Could not save this shortcut."
      fputs("Could not save keyboard shortcuts: \(error)\n", stderr)
    }
  }

  @discardableResult private func install(_ shortcut: CommandShortcut, for command: AppCommand)
    -> Bool
  {
    guard shortcut.isValid else {
      errors[command.rawValue] = "Choose a valid keyboard shortcut."
      return false
    }
    do {
      try hotkeys.register(command, shortcut: shortcut)
      errors[command.rawValue] = nil
      return true
    } catch {
      errors[command.rawValue] = error.localizedDescription
      return false
    }
  }
}
