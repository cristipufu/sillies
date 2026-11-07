import SwiftUI

/// Storage is a workspace page; its sections share one width, inset and action style.
struct VaultStorageView: View {
  @Environment(\.silliesTheme) private var theme
  let vault: SessionVaultStore
  let actions: SessionVaultModel
  private enum Layout {
    static let contentWidth: CGFloat = 680
    static let pageInset: CGFloat = 28
    static let sectionGap: CGFloat = 20
    static let cardInset: CGFloat = 20
    static let cornerRadius: CGFloat = 10
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Layout.sectionGap) {
        Button("Back to library", systemImage: "chevron.left") { actions.workspace.showLibrary() }
          .buttonStyle(.plain).foregroundStyle(theme.secondary)
        Text("Storage & retention").font(.system(size: 24, weight: .bold, design: .rounded))
        card { VaultStorageSummary(vault: vault, isPresented: actions.isPresented) }
        card {
          VStack(alignment: .leading, spacing: 16) {
            Label("Export & backup", systemImage: "externaldrive.badge.timemachine").font(.headline)
            Text(
              "Backups include Vault items and Trash. Export companion conversations from their Chat menus."
            )
            .font(.callout).foregroundStyle(theme.secondary)
            ViewThatFits(in: .horizontal) {
              HStack(spacing: 10) { exportActions }
              VStack(alignment: .leading, spacing: 10) { exportActions }
            }
            Divider().overlay(theme.border)
            VaultRestoreControls(vault: vault, actions: actions)
          }
        }
        card { VaultRetentionView(vault: vault) }
      }.frame(maxWidth: Layout.contentWidth, alignment: .leading)
        .padding(Layout.pageInset).frame(maxWidth: .infinity, alignment: .top)
    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var exportActions: some View {
    Group {
      Button("Export all as Markdown…") { actions.exportAll() }
      Button("Back up Vault…") { actions.backup() }
    }.buttonStyle(SoftButtonStyle()).disabled(!actions.canExport)
  }

  private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    content().frame(maxWidth: .infinity, alignment: .leading).padding(Layout.cardInset)
      .background(theme.card, in: RoundedRectangle(cornerRadius: Layout.cornerRadius))
      .overlay {
        RoundedRectangle(cornerRadius: Layout.cornerRadius).strokeBorder(
          theme.border, lineWidth: 0.5)
      }
  }
}
