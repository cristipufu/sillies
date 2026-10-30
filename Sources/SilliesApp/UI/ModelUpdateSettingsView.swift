import SwiftUI

struct ModelUpdateSettingsView: View {
  let model: ModelUpdatesPresentation
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Toggle(
        "Check downloaded models daily",
        isOn: Binding(
          get: { model.checksAutomatically },
          set: { if $0 { model.enableAutomaticChecks() } else { model.disableAutomaticChecks() } })
      )
      .font(.callout)
      HStack {
        if model.isChecking {
          ProgressView("Checking publishers…").controlSize(.small)
        } else if let date = model.snapshot.checkedAt {
          Text("Last checked \(date.formatted(date: .abbreviated, time: .shortened))")
            .font(.caption).foregroundStyle(SilliesTheme.secondary)
        }
        Spacer()
        Button("Check now") { model.checkNow() }.buttonStyle(SoftButtonStyle())
          .disabled(model.isChecking)
      }
      Text(
        "Checks use publisher metadata only. Updates download when you choose; active sessions keep their current model."
      )
      .font(.caption).foregroundStyle(SilliesTheme.secondary)
      .fixedSize(horizontal: false, vertical: true)
      if let error = model.error { Text(error).font(.caption).foregroundStyle(.red) }
    }
  }
}
