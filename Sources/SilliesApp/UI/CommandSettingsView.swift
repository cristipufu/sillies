import SilliesCore
import SwiftUI

struct CommandSettingsView: View {
  let shortcuts: CommandShortcuts

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(
        "Click a shortcut, then press a key with Command, Option, or Control. While editing a shortcut, Escape cancels and Delete clears it."
      )
      .font(.caption).foregroundStyle(SilliesTheme.secondary)
      if shortcuts.availability == .suspended {
        Text(
          "Companions are paused or unavailable. Assigned shortcuts stay reserved; resume the crew to use skills."
        )
        .font(.caption).foregroundStyle(SilliesTheme.secondary)
      }
      ForEach(CommandShortcutGroup.allCases) { group in
        VStack(alignment: .leading, spacing: 12) {
          Text(group.title).font(.system(.headline, design: .rounded))
          Text(group.explanation).font(.caption).foregroundStyle(SilliesTheme.secondary)
          ForEach(group.commands) { command in
            shortcutRow(command)
          }
        }.padding(14)
          .background(SilliesTheme.card, in: RoundedRectangle(cornerRadius: 14))
          .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(SilliesTheme.border))
      }
    }
  }

  private func shortcutRow(_ command: AppCommand) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(command.title)
        Spacer()
        ShortcutRecorder(
          shortcut: shortcuts.bindings[command.rawValue],
          begin: { shortcuts.stop() },
          finish: { shortcuts.start() },
          assign: { shortcuts.assign($0, to: command) }
        )
        .frame(width: 160, height: 27)
        .accessibilityLabel("Shortcut for \(command.title)")
      }
      Text(command.shortcutExplanation).font(.caption).foregroundStyle(SilliesTheme.secondary)
      if let error = shortcuts.errors[command.rawValue] {
        Text(error).font(.caption).foregroundStyle(.red)
      }
    }
  }
}
