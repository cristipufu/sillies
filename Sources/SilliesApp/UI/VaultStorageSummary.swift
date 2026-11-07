import SilliesCore
import SwiftUI

struct VaultStorageSummary: View {
  @Environment(\.silliesTheme) private var theme
  let vault: SessionVaultStore
  let isPresented: Bool
  @State private var usage: VaultStorageUsage?
  @State private var error: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("Stored on this Mac", systemImage: "internaldrive").font(.headline)
      if let usage {
        storageRow("Notes & transcripts", bytes: usage.databaseBytes)
        storageRow("Saved files", bytes: usage.attachmentBytes)
        storageRow("Search cache", bytes: usage.searchCacheBytes)
      } else if let error {
        Text(error).foregroundStyle(theme.danger).textSelection(.enabled)
      } else {
        ProgressView("Checking storage…").controlSize(.small)
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
      .task(id: isPresented) {
        guard isPresented else { return }
        do {
          let result = try await vault.library.storageUsage()
          guard !Task.isCancelled else { return }
          usage = result
          error = nil
        } catch is CancellationError { return } catch { self.error = error.localizedDescription }
      }
  }
  private func storageRow(_ label: LocalizedStringKey, bytes: Int64) -> some View {
    HStack {
      Text(label).foregroundStyle(theme.secondary)
      Spacer()
      Text(formatted(bytes)).monospacedDigit()
    }.font(.callout)
  }
  private func formatted(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }
}
