import AppKit
import SwiftUI

struct VaultRestoreControls: View {
  @Environment(\.silliesTheme) private var theme
  let vault: SessionVaultStore
  let actions: SessionVaultModel
  @State private var prepared: URL?
  @State private var error: String?
  @State private var isCancelling = false
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if prepared != nil {
        Label(
          "A backup is ready to restore on the next launch.",
          systemImage: "arrow.counterclockwise.circle")
        Text(
          "Your current Vault remains usable until you quit and reopen Sillies. It will be preserved in a recovery folder."
        )
        .font(.caption).foregroundStyle(theme.secondary)
        Button("Cancel prepared restore") { Task { await cancel() } }.disabled(isCancelling)
      } else {
        Button("Restore a Vault backup…") { actions.prepareRestore() }.disabled(!actions.canExport)
      }
      if let previous = vault.restoredPreviousDirectory {
        Text(
          "Your backup was restored. Automatic retention is off so you can review the recovered items."
        )
        .font(.caption).foregroundStyle(theme.secondary)
        Button("Show the previous Vault") {
          NSWorkspace.shared.activateFileViewerSelecting([previous])
        }
      }
      if let error {
        Text(error).font(.caption).foregroundStyle(theme.warning).textSelection(.enabled)
      }
    }.buttonStyle(SoftButtonStyle()).frame(maxWidth: .infinity, alignment: .leading)
      .task(id: actions.isExporting) {
        guard !actions.isExporting else { return }
        do {
          prepared = try await vault.library.preparedRestoreDirectory()
        } catch is CancellationError { return } catch { self.error = error.localizedDescription }
      }
  }
  private func cancel() async {
    isCancelling = true
    defer { isCancelling = false }
    do {
      try await vault.library.cancelPreparedRestore()
      prepared = nil
      error = nil
    } catch { self.error = error.localizedDescription }
  }
}
