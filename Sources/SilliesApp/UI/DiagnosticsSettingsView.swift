import SwiftUI

struct DiagnosticsSettingsView: View {
  @Environment(\.silliesTheme) private var theme
  let model: DiagnosticsPresentation
  let export: () -> Void

  var body: some View {
    SettingsCard(
      title: String(localized: "Diagnostics"),
      detail: String(localized: "Help explain a problem without sharing your conversations.")
    ) {
      Toggle(
        "Keep local diagnostics",
        isOn: Binding(
          get: { model.enabled }, set: { value in Task { await model.setEnabled(value) } }))
      Text("Technical events only. No messages, audio, Vault content or clipboard data.")
        .font(.caption).foregroundStyle(theme.secondary)
      Text("Up to 10 MB and 7 days. Older events are removed automatically. Nothing is uploaded.")
        .font(.caption).foregroundStyle(theme.secondary)
      HStack {
        Button("Export diagnostics", systemImage: "square.and.arrow.up", action: export)
          .buttonStyle(SoftButtonStyle())
        Button("Clear diagnostics") { Task { await model.clear() } }
          .buttonStyle(SoftButtonStyle())
        if model.isBusy { ProgressView().controlSize(.small) }
      }
      if let failure = model.failure {
        Text(failure).font(.caption).foregroundStyle(theme.danger).textSelection(.enabled)
      } else if let status = model.status {
        Text(status).font(.caption).foregroundStyle(theme.secondary).textSelection(.enabled)
      }
    }.disabled(model.isBusy).onAppear { model.refresh() }
  }
}
