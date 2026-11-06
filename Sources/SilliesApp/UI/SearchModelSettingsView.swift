import SilliesModelStore
import SwiftUI

struct SearchModelSettingsView: View {
  @Environment(\.silliesTheme) private var theme
  let model: SearchModelsPresentation
  private var downloads: SearchModelDownloads { model.downloads }
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      SettingsCard(
        title: String(localized: "Search & Memory"),
        detail: String(
          localized:
            "Find memories and Vault passages by meaning, even when you use different words. Keyword search always stays available."
        )
      ) {
        Label("Your recordings and text stay on this Mac.", systemImage: "lock.shield")
          .foregroundStyle(theme.secondary)
        Text(
          "Search includes meeting transcripts, screenshot text and Stash items. It does not change your chat model or create new memories."
        )
        .foregroundStyle(theme.secondary)
        indexStatus
        Button("Rebuild search index") { Task { await model.rebuild() } }
          .buttonStyle(SoftButtonStyle()).disabled(downloads.activeID != nil)
      }
      SettingsCard(
        title: String(localized: "Apple Natural Language"),
        detail: String(
          localized:
            "Uses available macOS language assets. Unsupported languages use keyword search.")
      ) {
        selectionButton(SearchModelEnvironment.appleID)
      }
      ForEach(downloads.manifests, id: \.modelID) { manifest in card(manifest) }
      if let error = downloads.error {
        Text(error).foregroundStyle(theme.secondary).textSelection(.enabled)
      }
    }.task { await model.observeStatus() }
  }
  @ViewBuilder private var indexStatus: some View {
    switch model.status {
    case .preparing: ProgressView("Preparing search…")
    case .paused: Text("Paused")
    case .failed(let message):
      Label(message, systemImage: "exclamationmark.triangle").textSelection(.enabled)
    case .indexed(let progress):
      if progress.processed < progress.total {
        ProgressView("Search passages prepared: \(progress.processed)")
      } else {
        Label("Ready", systemImage: "checkmark.circle")
      }
      Text(
        "Indexed for semantic search: \(progress.searchable). Keyword search stays available while the index is prepared."
      )
      .font(.caption).foregroundStyle(theme.secondary)
    }
  }
  private func card(_ manifest: SearchModelManifest) -> some View {
    let state = downloads.state(for: manifest.modelID)
    return SettingsCard(
      title: manifest.model.name,
      detail: LocalizedCatalogText.value(manifest.model.languagesDescription)
    ) {
      Text(
        "\(ByteCountFormatter.string(fromByteCount: manifest.downloadBytes, countStyle: .file)) download · \(manifest.model.minimumMemoryGB) GB memory required"
      )
      .font(.caption).foregroundStyle(theme.secondary)
      if let fraction = state.downloadFraction { ProgressView(value: fraction) }
      Text(state.label).font(.caption).foregroundStyle(theme.secondary).textSelection(.enabled)
      HStack {
        actions(manifest, state: state)
        Spacer()
        Link("Model details ↗", destination: manifest.model.sourceURL).font(.caption)
      }
    }
  }
  @ViewBuilder private func actions(_ manifest: SearchModelManifest, state: ModelInstallationState)
    -> some View
  {
    switch state {
    case .downloaded, .ready:
      selectionButton(manifest.modelID)
      Button("Remove", role: .destructive) { downloads.remove(manifest) }
        .buttonStyle(SoftButtonStyle()).disabled(downloads.activeID != nil)
    case .downloading, .verifying:
      Button("Pause download") { downloads.pauseDownload() }.buttonStyle(SoftButtonStyle())
    case .cancelling: ProgressView().controlSize(.small)
    default:
      Button(
        state == .paused ? String(localized: "Resume download") : String(localized: "Download")
      ) { downloads.download(manifest) }
      .buttonStyle(SoftButtonStyle()).disabled(
        downloads.activeID != nil || !downloads.supports(manifest))
    }
  }
  @ViewBuilder private func selectionButton(_ id: String) -> some View {
    if downloads.selectedModelID == id {
      Label("Selected", systemImage: "checkmark.circle.fill").foregroundStyle(theme.accent)
    } else {
      Button("Use for search") { downloads.select(id) }.buttonStyle(SoftButtonStyle())
        .disabled(downloads.activeID != nil)
    }
  }
}
