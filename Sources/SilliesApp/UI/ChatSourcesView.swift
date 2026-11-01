import SilliesCore
import SwiftUI

struct ChatSourcesView: View {
  @Environment(\.silliesTheme) private var theme
  let sources: [ChatSource]
  let vault: ChatVaultPresentation
  private static let previewHeight: CGFloat = 120

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      ForEach(sources) { source in
        VStack(alignment: .leading, spacing: 8) {
          Button {
            vault.openRecord(source.id)
          } label: {
            VStack(alignment: .leading, spacing: 8) {
              if let image = vault.store.cachedImage(for: source) {
                Image(nsImage: image).resizable().scaledToFit()
                  .frame(maxWidth: .infinity, maxHeight: Self.previewHeight)
                  .clipShape(RoundedRectangle(cornerRadius: 10))
              }
              HStack(alignment: .top, spacing: 8) {
                Image(systemName: source.imageFilename == nil ? "doc.text" : "photo")
                  .foregroundStyle(theme.accent)
                VStack(alignment: .leading, spacing: 4) {
                  Text(source.title).font(.callout.weight(.semibold)).lineLimit(2)
                  HStack {
                    Text(source.kind.title)
                    Text(source.createdAt, style: .date)
                  }.font(.caption).foregroundStyle(theme.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.forward").font(.caption).foregroundStyle(
                  theme.secondary)
              }
            }.contentShape(Rectangle())
          }.buttonStyle(.plain).help("Open in Vault")
          if !source.excerpt.isEmpty {
            Text(source.excerpt).font(.caption).foregroundStyle(theme.secondary)
              .lineLimit(3).textSelection(.enabled)
          }
          ForEach(source.links, id: \.absoluteString) { url in
            Link(destination: url) {
              Label(url.absoluteString, systemImage: "link").font(.caption).lineLimit(2)
            }.tint(theme.accent)
          }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.paper, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.border))
        .task(id: source.imageFilename) { vault.store.prepareImage(for: source) }
      }
    }
  }
}
