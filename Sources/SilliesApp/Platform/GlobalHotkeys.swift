import Carbon
import Foundation
import SilliesCore

/// Carbon delivers registered combinations only; no global key-content monitor is installed.
@MainActor
final class GlobalHotkeys {
  enum Edge { case pressed, released }
  private static let signature: OSType = 0x5349_4C4C
  private var handler: EventHandlerRef?
  private var registrations: [AppCommand: EventHotKeyRef] = [:]
  private var pressed: Set<AppCommand> = []
  var onEvent: ((AppCommand, Edge) -> Void)?
  var registeredCommands: Set<AppCommand> { Set(registrations.keys) }

  func register(_ command: AppCommand, shortcut: CommandShortcut) throws {
    try installHandler()
    guard let index = AppCommand.allCases.firstIndex(of: command) else { return }
    let identifier = EventHotKeyID(signature: Self.signature, id: UInt32(index + 1))
    var reference: EventHotKeyRef?
    let status = RegisterEventHotKey(
      shortcut.keyCode, carbonModifiers(shortcut.modifiers), identifier,
      GetApplicationEventTarget(), 0, &reference)
    guard status == noErr, let reference else {
      throw HotkeyError(
        "This shortcut could not be registered (\(status)). Choose another combination.")
    }
    unregister(command)
    registrations[command] = reference
  }

  func unregister(_ command: AppCommand) {
    if pressed.remove(command) != nil { onEvent?(command, .released) }
    if let reference = registrations.removeValue(forKey: command) {
      UnregisterEventHotKey(reference)
    }
  }

  func stop() {
    for command in Array(registrations.keys) { unregister(command) }
    if let handler { RemoveEventHandler(handler) }
    handler = nil
  }

  private func installHandler() throws {
    guard handler == nil else { return }
    var events = [
      EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
      EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
    ]
    let status = InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, context in
        guard let event, let context else { return OSStatus(eventNotHandledErr) }
        return MainActor.assumeIsolated {
          Unmanaged<GlobalHotkeys>.fromOpaque(context).takeUnretainedValue().receive(event)
        }
      }, events.count, &events, Unmanaged.passUnretained(self).toOpaque(), &handler)
    guard status == noErr else {
      throw HotkeyError("Keyboard shortcuts are unavailable (\(status)).")
    }
  }

  private func receive(_ event: EventRef) -> OSStatus {
    var identifier = EventHotKeyID()
    guard
      GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier) == noErr,
      identifier.signature == Self.signature, identifier.id > 0,
      Int(identifier.id) <= AppCommand.allCases.count
    else { return OSStatus(eventNotHandledErr) }
    let command = AppCommand.allCases[Int(identifier.id) - 1]
    if GetEventKind(event) == kEventHotKeyPressed {
      if pressed.insert(command).inserted { onEvent?(command, .pressed) }
    } else if pressed.remove(command) != nil {
      onEvent?(command, .released)
    }
    return noErr
  }

  private func carbonModifiers(_ modifiers: CommandShortcut.Modifiers) -> UInt32 {
    var value: UInt32 = 0
    for (flag, carbon) in [
      (CommandShortcut.Modifiers.command, cmdKey), (.option, optionKey),
      (.control, controlKey), (.shift, shiftKey),
    ] where modifiers.contains(flag) { value |= UInt32(carbon) }
    return value
  }
}

struct HotkeyError: LocalizedError {
  let message: String
  init(_ message: String) { self.message = message }
  var errorDescription: String? { message }
}
