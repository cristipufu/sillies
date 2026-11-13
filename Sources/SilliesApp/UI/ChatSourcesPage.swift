import SilliesCore
import SwiftUI

/// A saved reply's evidence is read inside the existing bubble, including repeated sources.
struct ChatSourcesPage: View {
  @Environment(\.silliesTheme) private var theme
  let sources: [ChatSource]
  let vault: ChatVaultPresentation
  let back: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      ChatPageHeader(title: String(localized: "Sources"), back: back)
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 20) {
          ForEach(sources) { source in
            VStack(alignment: .leading, spacing: 12) {
              Text(source.title).font(.headline)
              if source.passages.isEmpty {
                Text(source.excerpt).font(.callout).textSelection(.enabled)
              }
              ForEach(source.passages, id: \.self) { passage in
                ChatSourcePassageView(
                  passage: passage, source: source, vault: vault, presentation: .detail)
              }
              Button("Open in Vault", systemImage: "arrow.up.forward") {
                vault.openRecord(source.id)
              }
              .buttonStyle(.plain).font(.caption).foregroundStyle(theme.accent)
            }
          }
        }.frame(maxWidth: .infinity, alignment: .leading)
      }
    }.padding(16)
  }
}
