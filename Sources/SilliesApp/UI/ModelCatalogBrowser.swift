import SwiftUI

struct ModelCatalogEntry<Model>: Identifiable {
  let id: String
  let family: String
  let name: String
  let detail: String
  let state: ModelInstallationState
  let isSelected: Bool
  let model: Model
}

enum ModelCatalogFilter: CaseIterable, Identifiable {
  case all, installed, available
  var id: Self { self }
  var title: String {
    switch self {
    case .all: String(localized: "All models")
    case .installed: String(localized: "Installed")
    case .available: String(localized: "Available")
    }
  }
  func includes(_ state: ModelInstallationState) -> Bool {
    if state.needsCatalogAttention { return true }
    switch self {
    case .all: return true
    case .installed: return state.isInstalled
    case .available: return !state.isInstalled
    }
  }
}

/// Presentation shared by catalogs, while installation and capability actions stay with each provider.
struct ModelCatalogBrowser<Model, Content: View>: View {
  @Environment(\.silliesTheme) private var theme
  let entries: [ModelCatalogEntry<Model>]
  @ViewBuilder let content: (Model) -> Content
  @State private var filter = ModelCatalogFilter.all
  private var visible: [ModelCatalogEntry<Model>] { entries.filter { filter.includes($0.state) } }
  private var families: [String] {
    var seen = Set<String>()
    return visible.compactMap { seen.insert($0.family).inserted ? $0.family : nil }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Picker("Local models", selection: $filter) {
        ForEach(ModelCatalogFilter.allCases) { Text($0.title).tag($0) }
      }.pickerStyle(.segmented)
      if visible.isEmpty {
        Text("No models in this view.").font(.callout).foregroundStyle(theme.secondary)
      }
      ForEach(families, id: \.self) { family in
        VStack(alignment: .leading, spacing: 8) {
          if visible.contains(where: { $0.family == family && $0.name != family }) {
            Text(family).font(.callout.weight(.semibold)).foregroundStyle(theme.secondary)
          }
          ForEach(visible.filter { $0.family == family }) { entry in
            ModelCatalogRow(entry: entry, content: content)
          }
        }
      }
    }
  }
}

private struct ModelCatalogRow<Model, Content: View>: View {
  @Environment(\.silliesTheme) private var theme
  let entry: ModelCatalogEntry<Model>
  @ViewBuilder let content: (Model) -> Content
  @State private var expanded = false
  var body: some View {
    DisclosureGroup(
      isExpanded: Binding(
        get: { expanded || entry.state.needsCatalogAttention }, set: { expanded = $0 })
    ) {
      content(entry.model).padding(.top, 12)
    } label: {
      HStack(spacing: 10) {
        VStack(alignment: .leading, spacing: 5) {
          Text(entry.name).font(.callout.weight(.semibold)).foregroundStyle(theme.ink)
          Text(entry.detail).font(.caption).foregroundStyle(theme.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
        if entry.isSelected {
          Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.accent)
            .accessibilityLabel("Selected")
        } else if entry.state.isInstalled {
          Image(systemName: "internaldrive").foregroundStyle(theme.secondary)
            .accessibilityLabel("Installed")
        }
      }
    }
    .padding(16).background(theme.card, in: RoundedRectangle(cornerRadius: 12))
    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.border, lineWidth: 0.8))
  }
}
