import AppKit
import SilliesCore
import SwiftUI

struct VaultLinkCard: View {
  @Environment(\.silliesTheme) private var theme
  let link: VaultLink
  var image: NSImage?
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 12) {
        if let image {
          Image(nsImage: image).resizable().scaledToFill().frame(width: 64, height: 48).clipped()
            .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
          Image(
            systemName: link.kind == .video
              ? "play.rectangle.fill" : (link.kind == .post ? "quote.bubble.fill" : "globe")
          )
          .font(.system(size: 26)).foregroundStyle(theme.accent)
        }
        VStack(alignment: .leading, spacing: 5) {
          Text(link.title).font(.system(size: 14, weight: .semibold)).lineLimit(2)
          Text(link.author.isEmpty ? link.url.host ?? "" : link.author).font(.caption)
            .foregroundStyle(theme.secondary)
        }
        Spacer()
        Button {
          NSWorkspace.shared.open(link.url)
        } label: {
          Image(systemName: "arrow.up.right")
        }.buttonStyle(.plain).help("Open original")
      }
      if !link.description.isEmpty {
        Text(link.description).font(.system(size: 12)).lineLimit(2).textSelection(.enabled)
      }
      HStack {
        Text(link.url.absoluteString).font(.system(size: 10.5)).foregroundStyle(theme.secondary)
          .lineLimit(1).textSelection(.enabled)
        Spacer()
        if link.previewState == .pending { ProgressView().controlSize(.mini) }
      }
      if link.previewState == .unavailable {
        Text("Preview unavailable. Your saved link and notes are safe.").font(.caption)
          .foregroundStyle(theme.secondary)
      }
    }.padding(14).background(theme.soft, in: RoundedRectangle(cornerRadius: 9))
      .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(theme.border, lineWidth: 0.7) }
  }
}
