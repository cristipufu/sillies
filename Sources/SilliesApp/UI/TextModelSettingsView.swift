import SilliesModelStore
import SwiftUI

struct TextModelSettingsView: View {
  let model: TextModelsPresentation
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      SettingsCard(
        title: "Notes that speak your language",
        detail:
          "Choose the model for summaries, meeting suggestions and writing tools. Speech recognition is configured separately in Speech & Meetings."
      ) {
        Label("Your recordings and text stay on this Mac.", systemImage: "lock.shield")
          .foregroundStyle(SilliesTheme.secondary)
        Text(
          "Downloads are optional. Larger models use more storage and memory; language quality varies. First use takes longer while the model loads."
        )
        .foregroundStyle(SilliesTheme.secondary)
      }
      SettingsCard(
        title: "Apple Intelligence",
        detail:
          "Built into macOS. No Sillies model download. Available languages depend on Apple Intelligence on this Mac."
      ) {
        selectionButton(TextModelEnvironment.appleID)
      }
      if model.isLoading { ProgressView("Checking installed models…") }
      ForEach(model.manifests, id: \.modelID) { manifest in
        modelCard(manifest)
      }
      if let error = model.error {
        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(
          SilliesTheme.secondary
        )
        .textSelection(.enabled)
      }
    }.task { await model.load() }
  }

  private func modelCard(_ manifest: TextModelManifest) -> some View {
    let state = model.state(for: manifest.modelID)
    return SettingsCard(title: manifest.model.name, detail: manifest.model.detail) {
      Text(manifest.model.languagesDescription).foregroundStyle(SilliesTheme.secondary)
      Text(
        "\(ByteCountFormatter.string(fromByteCount: manifest.downloadBytes, countStyle: .file)) download · \(manifest.model.minimumMemoryGB) GB memory required"
      )
      .font(.caption).foregroundStyle(SilliesTheme.secondary)
      if !model.supports(manifest) {
        Label("This Mac has less memory than this model requires.", systemImage: "memorychip")
          .font(.caption).foregroundStyle(SilliesTheme.secondary)
      }
      if let fraction = state.downloadFraction {
        ProgressView(value: fraction).tint(SilliesTheme.accent)
      }
      Text(state.label).font(.caption).foregroundStyle(SilliesTheme.secondary).textSelection(
        .enabled)
      HStack(spacing: 12) {
        actions(manifest, state: state)
        Spacer(minLength: 0)
        Link("Model details ↗", destination: manifest.model.sourceURL).font(.caption)
      }
    }
  }

  @ViewBuilder private func actions(_ manifest: TextModelManifest, state: ModelInstallationState)
    -> some View
  {
    switch state {
    case .downloaded, .ready:
      selectionButton(manifest.modelID)
      Button("Remove", role: .destructive) { model.remove(manifest) }
        .buttonStyle(SoftButtonStyle()).disabled(model.activeID != nil)
    case .downloading, .verifying:
      Button("Pause download") { model.pauseDownload() }.buttonStyle(SoftButtonStyle())
    case .cancelling:
      ProgressView().controlSize(.small)
    default:
      Button(state == .paused ? "Resume download" : "Download") { model.download(manifest) }
        .buttonStyle(SoftButtonStyle()).disabled(model.activeID != nil || !model.supports(manifest))
    }
  }

  @ViewBuilder private func selectionButton(_ id: String) -> some View {
    if model.selectedModelID == id {
      Label("Selected", systemImage: "checkmark.circle.fill").foregroundStyle(SilliesTheme.accent)
    } else {
      Button("Use for notes & writing") { model.select(id) }.buttonStyle(SoftButtonStyle())
        .disabled(model.activeID != nil)
    }
  }
}
