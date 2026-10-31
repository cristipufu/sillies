import ServiceManagement
import SilliesCore
import SwiftUI

struct CommandSettingsView: View {
  let shortcuts: CommandShortcuts
  let login: LoginItemSettings
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Toggle(
        "Launch Sillies at login",
        isOn: Binding(
          get: { login.requested },
          set: { enabled in Task { await login.update(enabled ? .enabled : .disabled) } })
      )
      .disabled(login.isUpdating)
      if login.status == .requiresApproval {
        Button("Allow Sillies in Login Items…") { SMAppService.openSystemSettingsLoginItems() }
      }
      if let error = login.error { Text(error).foregroundStyle(.red).font(.caption) }
      Divider()
      Text(
        "Click a shortcut, then press a key with Command, Option, or Control. Escape cancels; Delete clears it."
      )
      .font(.caption).foregroundStyle(SilliesTheme.secondary)
      ForEach(AppCommand.allCases) { command in
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
          if let error = shortcuts.errors[command.rawValue] {
            Text(error).font(.caption).foregroundStyle(.red)
          }
        }
      }
    }
    .task { await login.refresh() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { Task { await login.refresh() } }
    }
  }
}
