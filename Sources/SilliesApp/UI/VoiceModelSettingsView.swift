import SilliesModelStore
import SwiftUI

struct VoiceModelSettingsView: View {
  @Environment(\.silliesTheme) private var theme
  let model: VoiceModelsPresentation

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      SettingsCard(
        title: String(localized: "A little voice. A lot of personality."),
        detail:
          String(
            localized:
              "Choose a local voice model for Talk. Each companion has its own preferred voice and personality."
          )
      ) {
        LabeledContent(
          "App default",
          value: model.manifests.first { $0.modelID == model.selectedModelID }?.model.name
            ?? String(localized: "Text replies only"))
        DisclosureGroup("Model information") {
          VStack(alignment: .leading, spacing: 10) {
            Label("Your conversations stay on this Mac.", systemImage: "lock.shield")
            Text(
              "Download a voice for spoken conversations. Chat works without one. Speech & Meetings controls listening; Local AI controls replies."
            )
            Text("Each model lists its supported languages and voice options below.")
          }.font(.caption).foregroundStyle(theme.secondary).padding(.top, 8)
        }
        if model.selectedModelID != VoiceModelEnvironment.disabledID {
          Button("Use text replies only") { model.select(VoiceModelEnvironment.disabledID) }
            .buttonStyle(SoftButtonStyle()).disabled(model.activeID != nil)
        }
      }
      if model.isLoading { ProgressView("Checking installed voices…") }
      ModelCatalogBrowser(
        entries: model.manifests.map { manifest in
          .init(
            id: manifest.modelID, family: manifest.model.family ?? manifest.model.name,
            name: manifest.model.name,
            detail: String(
              localized:
                "\(ByteCountFormatter.string(fromByteCount: manifest.downloadBytes, countStyle: .file)) download · \(manifest.model.minimumMemoryGB) GB memory required"
            ),
            state: model.state(for: manifest.modelID),
            isSelected: model.selectedModelID == manifest.modelID,
            model: manifest)
        }, content: card)
      if let error = model.error {
        Label(error, systemImage: "exclamationmark.triangle").textSelection(.enabled)
      }
    }.task { await model.load() }
  }

  private func card(_ manifest: TTSModelManifest) -> some View {
    let state = model.state(for: manifest.modelID)
    return VStack(alignment: .leading, spacing: 12) {
      Text(LocalizedCatalogText.value(manifest.model.detail)).font(.callout)
      DisclosureGroup("Supported languages (\(manifest.model.languages.count))") {
        Text(
          manifest.model.languages.map { Locale.current.localizedString(forLanguageCode: $0) ?? $0 }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .joined(separator: " · ")
        )
        .font(.caption).foregroundStyle(theme.secondary)
      }
      Text(manifest.model.license).font(.caption).foregroundStyle(theme.secondary)

      if !model.supports(manifest) {
        Label("This Mac has less memory than this model requires.", systemImage: "memorychip").font(
          .caption)
      }
      if let fraction = state.downloadFraction {
        ProgressView(value: fraction).tint(theme.accent)
      }
      Text(state.label).font(.caption).foregroundStyle(theme.secondary).textSelection(
        .enabled)
      HStack {
        ModelInstallationControls(
          model: model, manifest: manifest,
          selectionTitle: String(localized: "Use for Talk"), scope: .manage)
        Spacer(minLength: 0)
        Link("Model & license ↗", destination: manifest.model.sourceURL).font(.caption)
      }
    }
  }

}
