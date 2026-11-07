import AppKit
import SilliesCore
import SwiftUI

/// Uses the bounded preview cache; decoding and original-file reads belong to the media worker.
struct VaultScreenshotView: View {
  @Environment(\.silliesTheme) private var theme
  let vault: SessionVaultStore
  let source: SessionRecordHeader
  private enum Layout {
    static let inset: CGFloat = 20
    static let cornerRadius: CGFloat = 8
    static let controlSpacing: CGFloat = 16
  }

  var body: some View {
    VStack(spacing: 0) {
      switch vault.imageState(for: source) {
      case .available(let image):
        GeometryReader { geometry in
          Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: Layout.cornerRadius))
            .frame(width: geometry.size.width, height: geometry.size.height)
            .accessibilityLabel(Text("Screenshot"))
            .contextMenu {
              Button("Copy Image") { vault.copyImage(for: source) }
            }
        }.padding(Layout.inset)
      case .loading:
        ProgressView("Loading Vault item…").frame(maxWidth: .infinity, maxHeight: .infinity)
          .task(id: source.imageFilename) { vault.prepareImage(for: source) }
      case .unavailable:
        ContentUnavailableView {
          Label("Image unavailable", systemImage: "photo.badge.exclamationmark")
        } actions: {
          Button("Try again") { vault.prepareImage(for: source) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      HStack(spacing: Layout.controlSpacing) {
        Button("Copy Image", systemImage: "doc.on.doc") { vault.copyImage(for: source) }
          .disabled(vault.cachedImage(for: source) == nil)
        Spacer()
        if let url = vault.imageURL(for: source) {
          Button("Show image file", systemImage: "folder") {
            NSWorkspace.shared.activateFileViewerSelecting([url])
          }
        }
      }.buttonStyle(.plain).font(.caption).foregroundStyle(theme.secondary)
        .padding(.horizontal, Layout.inset).padding(.bottom, Layout.inset)
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
