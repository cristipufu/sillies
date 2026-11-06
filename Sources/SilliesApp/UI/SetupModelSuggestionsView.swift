import SilliesModelStore
import SwiftUI

struct SetupModelSuggestionsView: View {
  @Environment(\.silliesTheme) private var theme
  let model: SetupModelSuggestions
  let activity: SetupActivity
  let language: String
  let overrideID: String?
  let refresh: () -> Void
  @State private var expanded = false

  var body: some View {
    DisclosureGroup("Help me choose models", isExpanded: $expanded) {
      VStack(alignment: .leading, spacing: 14) {
        Text(
          "Installed models come first. Suggestions leave room for macOS and the other models this activity needs."
        )
        .font(.caption).foregroundStyle(theme.secondary)
        if overrideID == nil,
          let candidate = model.suggestedText(activity: activity, language: language)
        {
          suggestion(
            title: candidate.model.name,
            detail: LocalizedCatalogText.value(candidate.model.languagesDescription),
            manifest: candidate, presentation: model.text)
          if model.score(for: candidate) > 0,
            let comparisonURL = URL(
              string: "https://github.com/cristipufu/sillies/blob/main/docs/local-text-models.md")
          {
            Link(
              "Based on Sillies’ reviewed model comparison",
              destination: comparisonURL
            )
            .font(.caption)
          }
        }
        if activity == .talk, let candidate = model.suggestedVoice(language: language) {
          suggestion(
            title: candidate.model.name,
            detail: String(localized: "Supports the selected conversation language."),
            manifest: candidate, presentation: model.voice)
        }
        Text(
          "Memory use is an estimate. Language quality varies; you can explore every model in Settings."
        )
        .font(.caption).foregroundStyle(theme.secondary)
        if let error = model.error { Text(error).font(.caption).textSelection(.enabled) }
      }.padding(.top, 12)
    }.font(.callout.weight(.medium)).task { await model.load() }
      .onChange(of: model.text.selectedModelID) { refresh() }
      .onChange(of: model.voice.selectedModelID) { refresh() }
      .onChange(of: model.text.activeID) { refresh() }
      .onChange(of: model.voice.activeID) { refresh() }
      .onChange(of: model.speech.selectedModelID) { refresh() }
  }

  private func suggestion<Manifest: ModelArtifactManifest>(
    title: String, detail: String, manifest: Manifest,
    presentation: DownloadableModelsPresentation<Manifest>
  ) -> some View {
    let state = presentation.state(for: manifest.modelID)
    return VStack(alignment: .leading, spacing: 8) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text(title).font(.callout.weight(.semibold))
          Text(detail).font(.caption).foregroundStyle(theme.secondary)
        }
        Spacer()
        ModelInstallationControls(
          model: presentation, manifest: manifest,
          selectionTitle: String(localized: "Use this model"), scope: .choose)
      }
      if let fraction = state.downloadFraction {
        ProgressView(value: fraction).tint(theme.accent)
      }
      Text(state.label).font(.caption).foregroundStyle(theme.secondary).textSelection(.enabled)
      Text(ByteCountFormatter.string(fromByteCount: manifest.downloadBytes, countStyle: .file))
        .font(.caption).foregroundStyle(theme.secondary)
    }.padding(14).background(theme.card, in: RoundedRectangle(cornerRadius: 12))
      .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.border))
  }
}
