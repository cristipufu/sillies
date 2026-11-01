import ServiceManagement
import SwiftUI

struct GeneralSettingsPage: View {
  @Environment(\.silliesTheme) private var theme
  let controller: CompanionController
  let login: LoginItemSettings?
  var language: LanguagePreferences? = nil
  var body: some View {
    if let language { LanguageSettingsView(model: language) }
    if let login {
      SettingsCard(
        title: String(localized: "Start the day together"),
        detail: String(localized: "Have your companions ready when you sign in.")
      ) {
        LoginSettingsView(model: login)
      }
    }
    SettingsCard(title: String(localized: "App updates")) { UpdatesSettingsView() }
    SettingsCard(
      title: String(localized: "Made for your Mac"),
      detail: String(localized: "Speech, writing, and saved captures are processed locally.")
    ) {
      Text(
        "Recording starts only when you ask. Your Vault and recent writing stay on this Mac; model downloads and update checks use the internet."
      )
      .font(.caption).foregroundStyle(theme.secondary)
      Button("Open Session Vault", systemImage: "archivebox") { controller.onOpenVault?(nil) }
        .buttonStyle(SoftButtonStyle())
    }
    DisclosureGroup("Diagnostics") {
      VStack(spacing: 10) {
        diagnostic(String(localized: "Companions"), value: "\(controller.liveCount)")
        diagnostic(
          String(localized: "Movement"),
          value: controller.movingCount == 0
            ? String(localized: "Stopped") : String(localized: "\(controller.movingCount) moving"))
        diagnostic(
          String(localized: "Power mode"),
          value: controller.tracker.isLowPower
            ? String(localized: "Low Power") : String(localized: "Normal"))
        diagnostic(String(localized: "Recent reaction"), value: controller.lastReaction)
      }.padding(.top, 12)
    }.font(.caption).foregroundStyle(theme.secondary)
  }
  private func diagnostic(_ title: String, value: String) -> some View {
    HStack {
      Text(title)
      Spacer()
      Text(value).monospacedDigit()
    }
  }
}

private struct LoginSettingsView: View {
  @Environment(\.silliesTheme) private var theme
  let model: LoginItemSettings
  @Environment(\.scenePhase) private var scenePhase
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Toggle(
        "Launch Sillies at login",
        isOn: Binding(
          get: { model.requested },
          set: { enabled in Task { await model.update(enabled ? .enabled : .disabled) } })
      )
      .disabled(model.isUpdating)
      if model.status == .requiresApproval {
        Button("Allow Sillies in Login Items…") { SMAppService.openSystemSettingsLoginItems() }
          .buttonStyle(SoftButtonStyle())
      }
      if let error = model.error { Text(error).font(.caption).foregroundStyle(theme.danger) }
    }.task { await model.refresh() }
      .onChange(of: scenePhase) { _, phase in
        if phase == .active { Task { await model.refresh() } }
      }
  }
}
