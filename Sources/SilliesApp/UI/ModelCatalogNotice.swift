import SilliesModelStore
import SwiftUI

struct ModelCatalogNotice<Manifest: ModelArtifactManifest>: View {
  @Environment(\.silliesTheme) private var theme
  let model: DownloadableModelsPresentation<Manifest>

  var body: some View {
    if let error = model.error {
      VStack(alignment: .leading, spacing: 8) {
        Label(error, systemImage: "exclamationmark.triangle")
          .foregroundStyle(theme.secondary).textSelection(.enabled)
        if model.manifests.isEmpty, !model.isLoading {
          Button("Try again") { model.start() }.buttonStyle(SoftButtonStyle())
        }
      }
    }
  }
}
