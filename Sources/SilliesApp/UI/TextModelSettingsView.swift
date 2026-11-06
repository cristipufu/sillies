import SilliesModelStore
import SwiftUI

struct TextModelSettingsView: View {
  @Environment(\.silliesTheme) private var theme
  let model: TextModelsPresentation
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      SettingsCard(
        title: String(localized: "A mind for every conversation"),
        detail:
          String(
            localized:
              "Choose the app’s default reply model for Chat, Talk, meeting notes and writing. Companions can also have their own model."
          )
      ) {
        Label("Your recordings and text stay on this Mac.", systemImage: "lock.shield")
          .foregroundStyle(theme.secondary)
        Text(
          "Downloads are optional. Larger models use more storage and memory; language quality varies. First use takes longer while the model loads."
        )
        .foregroundStyle(theme.secondary)
      }
      SettingsCard(
        title: String(localized: "Apple Intelligence"),
        detail:
          String(
            localized:
              "Built into macOS. No Sillies model download. Available languages depend on Apple Intelligence on this Mac."
          )
      ) {
        selectionButton(model.fallbackModelID)
      }
      if model.isLoading { ProgressView("Checking installed models…") }
      ForEach(model.manifests, id: \.modelID) { manifest in
        modelCard(manifest)
      }
      if let error = model.error {
        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(
          theme.secondary
        )
        .textSelection(.enabled)
      }
    }.task { await model.load() }
  }

  private func modelCard(_ manifest: TextModelManifest) -> some View {
    let state = model.state(for: manifest.modelID)
    return SettingsCard(
      title: manifest.model.name, detail: LocalizedCatalogText.value(manifest.model.detail)
    ) {
      Text(LocalizedCatalogText.value(manifest.model.languagesDescription)).foregroundStyle(
        theme.secondary)
      Text(
        "\(ByteCountFormatter.string(fromByteCount: manifest.downloadBytes, countStyle: .file)) download · \(manifest.model.minimumMemoryGB) GB memory required"
      )
      .font(.caption).foregroundStyle(theme.secondary)
      if !model.supports(manifest) {
        Label("This Mac has less memory than this model requires.", systemImage: "memorychip")
          .font(.caption).foregroundStyle(theme.secondary)
      }
      if let fraction = state.downloadFraction {
        ProgressView(value: fraction).tint(theme.accent)
      }
      Text(state.label).font(.caption).foregroundStyle(theme.secondary).textSelection(
        .enabled)
      HStack(spacing: 12) {
        ModelInstallationControls(
          model: model, manifest: manifest,
          selectionTitle: String(localized: "Use as app default"), scope: .manage)
        Spacer(minLength: 0)
        Link("Model details ↗", destination: manifest.model.sourceURL).font(.caption)
      }
    }
  }

  @ViewBuilder private func selectionButton(_ id: String) -> some View {
    if model.selectedModelID == id {
      Label("Selected", systemImage: "checkmark.circle.fill").foregroundStyle(theme.accent)
    } else {
      Button("Use as app default") { model.select(id) }.buttonStyle(SoftButtonStyle())
        .disabled(model.activeID != nil)
    }
  }
}
