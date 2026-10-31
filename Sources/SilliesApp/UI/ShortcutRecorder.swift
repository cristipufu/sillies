import AppKit
import Carbon
import SilliesCore
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
  let shortcut: CommandShortcut?
  let begin: () -> Void
  let finish: () -> Void
  let assign: (CommandShortcut?) -> Void

  func makeNSView(context: Context) -> ShortcutRecorderButton { ShortcutRecorderButton() }
  func updateNSView(_ view: ShortcutRecorderButton, context: Context) {
    view.shortcut = shortcut
    view.onBegin = begin
    view.onFinish = finish
    view.onAssign = assign
    view.refreshTitle()
  }
  static func dismantleNSView(_ view: ShortcutRecorderButton, coordinator: ()) { view.cancel() }
}

@MainActor
final class ShortcutRecorderButton: NSButton {
  var shortcut: CommandShortcut?
  var onBegin: (() -> Void)?
  var onFinish: (() -> Void)?
  var onAssign: ((CommandShortcut?) -> Void)?
  private var recording = false
  override var acceptsFirstResponder: Bool { true }

  init() {
    super.init(frame: .zero)
    bezelStyle = .rounded
    target = self
    action = #selector(beginRecording)
    refreshTitle()
  }
  required init?(coder: NSCoder) { return nil }

  func refreshTitle() {
    title = recording ? "Press shortcut…" : shortcut?.display ?? "Set shortcut…"
  }

  @objc private func beginRecording() {
    window?.makeFirstResponder(self)
    recording = true
    onBegin?()
    refreshTitle()
  }

  override func keyDown(with event: NSEvent) {
    guard recording else {
      super.keyDown(with: event)
      return
    }
    switch event.keyCode {
    case UInt16(kVK_Escape): cancel()
    case UInt16(kVK_Delete), UInt16(kVK_ForwardDelete):
      onAssign?(nil)
      cancel()
    default:
      var modifiers: CommandShortcut.Modifiers = []
      for (native, flag) in [
        (NSEvent.ModifierFlags.command, CommandShortcut.Modifiers.command),
        (.option, .option), (.control, .control), (.shift, .shift),
      ] where event.modifierFlags.contains(native) { modifiers.insert(flag) }
      let label =
        event.keyCode == UInt16(kVK_Space)
        ? "Space" : (event.charactersIgnoringModifiers ?? "").uppercased()
      onAssign?(
        CommandShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, keyLabel: label))
      cancel()
    }
  }

  func cancel() {
    guard recording else { return }
    recording = false
    onFinish?()
    refreshTitle()
  }

  override func resignFirstResponder() -> Bool {
    cancel()
    return super.resignFirstResponder()
  }
}
