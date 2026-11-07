import SilliesCore
import SwiftUI

struct VaultPassageMatchesView: View {
  @Environment(\.silliesTheme) private var theme
  let header: VaultDocumentHeader
  let workspace: VaultWorkspaceModel
  private var isExpanded: Bool { workspace.passageMatches.recordID == header.id }
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let location = header.match {
        Text(Self.label(location, seconds: header.matchSeconds)).font(.system(size: 10.5))
          .foregroundStyle(theme.accent)
      }
      if !workspace.searchText.isEmpty {
        Button(
          isExpanded ? String(localized: "Hide passages") : String(localized: "Matching passages")
        ) {
          workspace.passageMatches.toggle(header.id, query: workspace.query)
        }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(theme.accent)
      }
      if isExpanded {
        if workspace.passageMatches.isLoading { ProgressView().controlSize(.mini) }
        if let error = workspace.passageMatches.error {
          Text(error).font(.caption).foregroundStyle(theme.warning)
        }
        ForEach(workspace.passageMatches.passages) { passage in
          Button {
            workspace.visit(passage.location)
          } label: {
            VStack(alignment: .leading, spacing: 4) {
              Text(Self.label(passage.location, seconds: passage.startSeconds)).font(
                .system(size: 10.5, weight: .semibold))
              Text(passage.excerpt).font(.system(size: 12)).lineLimit(3)
            }.padding(.leading, 8).overlay(alignment: .leading) {
              Rectangle().fill(theme.accent.opacity(0.3)).frame(width: 2)
            }
          }.buttonStyle(.plain)
        }
        if workspace.passageMatches.passages.count == VaultPassageMatch.maximumPerItem {
          Text("Showing the best 20 passages in this item. Narrow your search to find others.")
            .font(.caption2).foregroundStyle(theme.secondary)
        }
      }
    }
  }
  private static func label(_ location: VaultBlockLocation, seconds: Double?) -> String {
    guard let seconds else { return location.section.title }
    return "\(location.section.title) · \(SessionRecord.formatDuration(seconds))"
  }
}
