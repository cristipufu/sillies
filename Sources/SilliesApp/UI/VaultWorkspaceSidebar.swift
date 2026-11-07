import SilliesCore
import SwiftUI

struct VaultWorkspaceSidebar: View {
  @Environment(\.silliesTheme) private var theme
  @Bindable var model: VaultWorkspaceModel
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(spacing: 10) {
        Image(systemName: "archivebox.fill").foregroundStyle(theme.accent)
        Text("Your Vault").font(.system(size: 18, weight: .bold, design: .rounded))
      }.padding(.horizontal, 10).padding(.top, 8)
      ScrollView {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(VaultWorkspaceQuery.Scope.allCases.filter { $0 != .trash }, id: \.self) { scope in
            row(
              scope.title, symbol: scope.symbol,
              selected: model.sidebarSelection == .scope(scope)
            ) {
              model.selectScope(scope)
            }
          }
          sectionHeading("Collections") { model.begin(.collection) }.padding(.top, 20)
          ForEach(model.collections) { collection in
            row(
              collection.name, symbol: "folder",
              selected: model.sidebarSelection == .collection(collection.id)
            ) {
              model.selectCollection(collection.id)
            }
            .contextMenu {
              Button("Rename…") { model.begin(.renameCollection(collection.id)) }
              Button("Remove collection") { Task { await model.removeCollection(collection.id) } }
            }
          }
          if model.collections.isEmpty {
            Text("Bring related things together.").font(.caption).foregroundStyle(theme.secondary)
              .padding(.horizontal, 10)
          }
          sectionHeading("Saved searches") { model.begin(.savedSearch) }.padding(.top, 20)
          ForEach(model.savedSearches) { saved in
            row(saved.name, symbol: "magnifyingglass", selected: false) {
              model.apply(saved)
            }
            .contextMenu {
              Button("Rename…") { model.begin(.renameSearch(saved.id)) }
              Button("Remove saved search") { Task { await model.removeSearch(saved.id) } }
            }
          }
        }
      }
      Divider().overlay(theme.border)
      VStack(spacing: 4) {
        row(
          String(localized: "Trash"), symbol: "trash",
          selected: model.sidebarSelection == .scope(.trash)
        ) {
          model.selectScope(.trash)
        }
        row(
          String(localized: "Storage & retention"), symbol: "externaldrive",
          selected: model.sidebarSelection == .storage
        ) { model.showStorage() }
      }
      Label("On your Mac", systemImage: "lock.shield").font(.caption).foregroundStyle(
        theme.secondary
      ).padding(.horizontal, 10)
    }.padding(12).frame(maxHeight: .infinity, alignment: .topLeading).background(
      theme.soft.opacity(0.38))
  }

  private func sectionHeading(_ title: LocalizedStringKey, add: @escaping () -> Void) -> some View {
    HStack {
      Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.secondary)
      Spacer()
      Button(action: add) { Image(systemName: "plus") }.buttonStyle(.plain).help(title)
    }.padding(.horizontal, 10).padding(.bottom, 6)
  }
  private func row(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      Label {
        Text(title).lineLimit(1)
      } icon: {
        Image(systemName: symbol).frame(width: 18)
      }
      .font(.system(size: 13, weight: selected ? .semibold : .regular))
      .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(
        .vertical, 8
      )
      .foregroundStyle(selected ? theme.accent : theme.ink)
      .background(
        selected ? theme.accent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 7))
    }.buttonStyle(.plain)
  }
}
