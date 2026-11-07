import SwiftUI

/// Distinguish an empty category from a search/filter that hid existing items.
struct VaultEmptyState: View {
  @Environment(\.silliesTheme) private var theme
  let model: VaultWorkspaceModel
  private var isFiltered: Bool { !model.searchText.isEmpty || model.activeFilterCount > 0 }
  private var title: String {
    if isFiltered { return String(localized: "No matching items") }
    switch model.scope {
    case .trash: return String(localized: "Trash is empty")
    case .starred: return String(localized: "Starred")
    default: return String(localized: "A little space for everything")
    }
  }
  private var message: String {
    if isFiltered { return String(localized: "Try different words or choose All items.") }
    switch model.scope {
    case .trash: return String(localized: "Items you move to Trash appear here.")
    case .starred: return String(localized: "Star an item to find it here.")
    case .meetings, .screenshots: return String(localized: "Saved items will appear here.")
    default: return String(localized: "Save a note, a link or a moment worth keeping.")
    }
  }

  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: model.scope == .trash ? "trash" : model.scope.symbol)
        .font(.system(size: 28, weight: .light)).foregroundStyle(theme.secondary.opacity(0.6))
      Text(title).font(.system(size: 14, weight: .semibold))
      Text(message).font(.system(size: 12)).foregroundStyle(theme.secondary)
      if isFiltered {
        if model.activeFilterCount > 0 {
          Button("Clear filters", action: model.clearFilters)
        }
        if !model.searchText.isEmpty {
          Button("Clear search") { model.updateSearchText("") }
        }
      } else if model.scope == .links {
        Button("Save link", systemImage: "link.badge.plus") { model.begin(.link) }
      }
    }.buttonStyle(SoftButtonStyle()).multilineTextAlignment(.center).padding(24)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
