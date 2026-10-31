import SilliesCore
import SwiftUI

struct VaultRetentionView: View {
  let vault: SessionVaultStore
  @Environment(\.dismiss) private var dismiss
  @State private var selection = VaultRetentionPolicy.keepAll
  @State private var confirmsDeletion = false
  @State private var confirmsClear = false
  private var count: Int { selection.expired(in: vault.records).count }
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      SessionIdentityHeader(title: "Keep what matters", symbol: "archivebox") {
        Text("Session Vault · Retention")
      } accessory: {
        EmptyView()
      }
      Text(
        "Vault records stay until you delete them by default. Writing has its own 20-result recovery history."
      )
      Picker("Retention", selection: $selection) {
        ForEach(VaultRetentionPolicy.allCases, id: \.self) { Text($0.title).tag($0) }
      }
      Text(
        "Protected records and Pocket Stash items are never automatically trimmed. Choosing a limit deletes older unprotected captures and their saved attachments, now and as new captures arrive."
      )
      .font(.callout).foregroundStyle(SilliesTheme.secondary)
      if count > 0 {
        Text("This change will delete \(count) existing capture(s).").foregroundStyle(.orange)
      }
      HStack {
        Button("Cancel") { dismiss() }.buttonStyle(SoftButtonStyle())
        Spacer()
        Button(count > 0 ? "Review deletion…" : "Save") {
          if count > 0 { confirmsDeletion = true } else { apply() }
        }.buttonStyle(.borderedProminent)
          .disabled(!vault.isReadyForRetention)
      }
      Divider()
      Button("Delete all Vault records…", role: .destructive) { confirmsClear = true }
        .disabled(!vault.isReadyForRetention || vault.records.isEmpty)
    }.padding(24).frame(width: 470)
      .background(SilliesTheme.paper).foregroundStyle(SilliesTheme.ink).tint(SilliesTheme.accent)
      .onAppear { selection = vault.retentionPolicy }
      .confirmationDialog(
        "Delete \(count) captures and their attachments?", isPresented: $confirmsDeletion
      ) {
        Button("Apply and delete \(count) captures", role: .destructive) { apply() }
      }
      .confirmationDialog(
        "Delete every Vault record, including protected sessions and Pocket Stash items? Saved attachments will also be deleted.",
        isPresented: $confirmsClear
      ) {
        Button("Delete all \(vault.records.count) records", role: .destructive) {
          vault.clearAll()
          dismiss()
        }
      }
  }
  private func apply() {
    vault.applyRetention(selection)
    dismiss()
  }
}
