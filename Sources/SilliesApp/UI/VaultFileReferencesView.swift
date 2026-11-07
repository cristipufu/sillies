import SilliesCore
import SwiftUI

struct VaultFileReferencesView: View {
  @Environment(\.silliesTheme) private var theme
  let model: VaultFileReferencesModel
  let relink: (VaultFileReference) -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      if model.isLoading && model.references.isEmpty {
        ProgressView().controlSize(.small).accessibilityLabel("Loading Vault item…")
      }
      if !model.references.isEmpty {
        Text("External files").font(.headline)
        Text(
          "These files stay in their original locations. Removing a Vault item never deletes them."
        )
        .font(.caption).foregroundStyle(theme.secondary)
      }
      if let error = model.error {
        Text(error).font(.caption).foregroundStyle(theme.warning).textSelection(.enabled)
      }
      ForEach(model.references) { reference in
        VStack(alignment: .leading, spacing: 6) {
          Label(reference.url.lastPathComponent, systemImage: "doc").font(.callout.weight(.medium))
          Text(reference.path).font(.caption).foregroundStyle(theme.secondary).textSelection(
            .enabled)
          HStack(spacing: 14) {
            Button("Open") { Task { await model.open(reference) } }
            Button("Show in Finder") { model.reveal(reference) }
            Button("Relink…") { relink(reference) }
          }.font(.caption).buttonStyle(.plain).foregroundStyle(theme.accent)
        }
      }
    }
  }
}
