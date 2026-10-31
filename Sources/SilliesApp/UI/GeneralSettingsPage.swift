import ServiceManagement
import SwiftUI

struct GeneralSettingsPage: View {
  let controller: CompanionController
  let login: LoginItemSettings?
  var body: some View {
    if let login {
      SettingsCard(
        title: "Start the day together", detail: "Have your companions ready when you sign in."
      ) {
        LoginSettingsView(model: login)
      }
    }
    SettingsCard(title: "App updates") { UpdatesSettingsView() }
    SettingsCard(
      title: "Made for your Mac",
      detail: "Speech, writing, and saved captures are processed locally."
    ) {
      Text(
        "Recording starts only when you ask. Your Vault and recent writing stay on this Mac; model downloads and update checks use the internet."
      )
      .font(.caption).foregroundStyle(SilliesTheme.secondary)
      Button("Open Session Vault", systemImage: "archivebox") { controller.onOpenVault?(nil) }
        .buttonStyle(SoftButtonStyle())
    }
    DisclosureGroup("Diagnostics") {
      VStack(spacing: 10) {
        diagnostic("Companions", value: "\(controller.liveCount)")
        diagnostic(
          "Movement",
          value: controller.movingCount == 0 ? "Stopped" : "\(controller.movingCount) moving")
        diagnostic("Power mode", value: controller.tracker.isLowPower ? "Low Power" : "Normal")
        diagnostic("Recent reaction", value: controller.lastReaction)
      }.padding(.top, 12)
    }.font(.caption).foregroundStyle(SilliesTheme.secondary)
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
      if let error = model.error { Text(error).font(.caption).foregroundStyle(.red) }
    }.task { await model.refresh() }
      .onChange(of: scenePhase) { _, phase in
        if phase == .active { Task { await model.refresh() } }
      }
  }
}
