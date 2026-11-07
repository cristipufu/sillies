import SilliesCore
import SwiftUI

struct VaultRetentionView: View {
  @Environment(\.silliesTheme) private var theme
  let vault: SessionVaultStore
  @State private var selection = VaultRetentionPolicy.keepAll
  @State private var confirmsDeletion = false
  @State private var confirmsClear = false
  private var count: Int { selection.limit.map { max(0, vault.eligibleRetentionCount - $0) } ?? 0 }
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Label("Keep what matters", systemImage: "archivebox").font(.headline)
      Text(
        "Vault records stay until you delete them by default. Writing has its own 20-result recovery history."
      ).font(.callout).foregroundStyle(theme.secondary)
      retentionPicker.disabled(!vault.isReadyForRetention)
      Text(
        "Protected records and Pocket Stash items are never automatically trimmed. Choosing a limit deletes older unprotected captures and their saved attachments, now and as new captures arrive."
      )
      .font(.callout).foregroundStyle(theme.secondary)
      if count > 0 {
        Text("This change will delete \(count) existing capture(s).").foregroundStyle(
          theme.warning)
      }
      if selection != vault.retentionPolicy {
        HStack {
          Button("Cancel") { selection = vault.retentionPolicy }.buttonStyle(SoftButtonStyle())
          Spacer()
          Button(count > 0 ? String(localized: "Review deletion…") : String(localized: "Save")) {
            if count > 0 { confirmsDeletion = true } else { apply() }
          }.buttonStyle(AccentButtonStyle())
            .disabled(!vault.isReadyForRetention)
        }
      }
      Divider().overlay(theme.border)
      Button("Delete all Vault records…", role: .destructive) { confirmsClear = true }
        .buttonStyle(.plain).foregroundStyle(theme.danger)
        .disabled(!vault.isReadyForRetention || vault.recordCount == 0)
    }.frame(maxWidth: .infinity, alignment: .leading)
      .foregroundStyle(theme.ink).tint(theme.accent)
      .onAppear { selection = vault.retentionPolicy }
      .onChange(of: vault.retentionPolicy) { old, current in
        if selection == old { selection = current }
      }
      .confirmationDialog(
        "Delete \(count) captures and their attachments?", isPresented: $confirmsDeletion
      ) {
        Button("Apply and delete \(count) captures", role: .destructive) { apply() }
      }
      .confirmationDialog(
        "Delete every Vault record, including protected sessions and Pocket Stash items? Saved attachments will also be deleted.",
        isPresented: $confirmsClear
      ) {
        Button("Delete all \(vault.recordCount) records", role: .destructive) {
          vault.clearAll()
        }
      }
  }
  private var retentionPicker: some View {
    HStack {
      Text("Retention").font(.callout)
      Spacer(minLength: 12)
      Menu {
        Picker("Retention", selection: $selection) {
          ForEach(VaultRetentionPolicy.allCases, id: \.self) { Text($0.title).tag($0) }
        }
      } label: {
        Text(selection.title).foregroundStyle(theme.ink).padding(.vertical, 7).padding(
          .horizontal, 10
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 6))
      }.menuStyle(.borderlessButton)
    }
  }
  private func apply() {
    vault.applyRetention(selection)
  }
}
