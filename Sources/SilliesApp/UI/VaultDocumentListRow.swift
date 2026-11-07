import SilliesCore
import SwiftUI

struct VaultDocumentListRow: View {
  @Environment(\.silliesTheme) private var theme
  let header: VaultDocumentHeader
  let workspace: VaultWorkspaceModel

  private enum Layout {
    static let horizontalSpacing: CGFloat = 10
    static let textSpacing: CGFloat = 4
    static let verticalPadding: CGFloat = 6
    static let iconWidth: CGFloat = 25
    static let iconHeight: CGFloat = 26
    static let iconRadius: CGFloat = 6
    static let iconFontSize: CGFloat = 15
    static let titleFontSize: CGFloat = 13
    static let metadataFontSize: CGFloat = 10.5
    static let starFontSize: CGFloat = 10
    static let iconBackgroundOpacity = 0.08
    static let titleLines = 2
  }

  var body: some View {
    HStack(alignment: .top, spacing: Layout.horizontalSpacing) {
      Image(systemName: header.symbol).font(.system(size: Layout.iconFontSize))
        .foregroundStyle(theme.accent)
        .frame(width: Layout.iconWidth, height: Layout.iconHeight)
        .background(
          theme.accent.opacity(Layout.iconBackgroundOpacity),
          in: RoundedRectangle(cornerRadius: Layout.iconRadius))
      VStack(alignment: .leading, spacing: Layout.textSpacing) {
        titleRow
        HStack(spacing: Layout.textSpacing) {
          Text(header.source.createdAt.formatted(date: .abbreviated, time: .omitted))
          if !header.source.characterName.isEmpty { Text("· \(header.source.characterName)") }
        }.font(.system(size: Layout.metadataFontSize)).foregroundStyle(theme.secondary)
        if header.match != nil || !workspace.searchText.isEmpty {
          VaultPassageMatchesView(header: header, workspace: workspace)
        }
      }
    }.padding(.vertical, Layout.verticalPadding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .draggable(VaultRecordTransfer(id: header.id))
  }

  private var titleRow: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(header.title).font(.system(size: Layout.titleFontSize, weight: .semibold))
        .lineLimit(Layout.titleLines)
      if header.metadata.isStarred {
        Image(systemName: "star.fill").font(.system(size: Layout.starFontSize))
          .foregroundStyle(theme.accent)
      }
    }
  }
}
