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
        Label("Your conversations stay on this Mac.", systemImage: "lock.shield")
        Text(
          "Download a voice for spoken conversations. Chat works without one. Speech & Meetings controls listening; Local AI controls replies."
        )
        .foregroundStyle(theme.secondary)
        Text("Each model lists its supported languages and voice options below.")
          .font(.caption).foregroundStyle(theme.secondary)
        if model.selectedModelID == VoiceModelEnvironment.disabledID {
          Label("Text replies only", systemImage: "text.bubble").foregroundStyle(
            theme.accent)
        } else {
          Button("Use text replies only") { model.select(VoiceModelEnvironment.disabledID) }
            .buttonStyle(SoftButtonStyle()).disabled(model.activeID != nil)
        }
      }
      if model.isLoading { ProgressView("Checking installed voices…") }
      ForEach(model.manifests, id: \.modelID) { manifest in card(manifest) }
      if let error = model.error {
        Label(error, systemImage: "exclamationmark.triangle").textSelection(.enabled)
      }
    }.task { await model.load() }
  }

  private func card(_ manifest: TTSModelManifest) -> some View {
    let state = model.state(for: manifest.modelID)
    return SettingsCard(
      title: manifest.model.name, detail: LocalizedCatalogText.value(manifest.model.detail)
    ) {
      DisclosureGroup("Supported languages (\(manifest.model.languages.count))") {
        Text(
          manifest.model.languages.map { Locale.current.localizedString(forLanguageCode: $0) ?? $0 }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .joined(separator: " · ")
        )
        .font(.caption).foregroundStyle(theme.secondary)
      }
      Text(manifest.model.license).font(.caption).foregroundStyle(theme.secondary)
      Text(
        "\(ByteCountFormatter.string(fromByteCount: manifest.downloadBytes, countStyle: .file)) download · \(manifest.model.minimumMemoryGB) GB memory required"
      )
      .font(.caption).foregroundStyle(theme.secondary)
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
