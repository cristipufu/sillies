import SilliesCore
import SwiftUI

struct VaultWorkspaceToolbar: View {
  @Environment(\.silliesTheme) private var theme
  @Bindable var model: VaultWorkspaceModel
  @Binding var navigationVisible: Bool
  @FocusState private var searchFocused: Bool
  var body: some View {
    HStack(spacing: 14) {
      Button {
        navigationVisible.toggle()
      } label: {
        Image(systemName: "sidebar.left")
      }
      .help("Show library navigation")
      .accessibilityLabel("Show library navigation")
      HStack(spacing: 10) {
        Button(action: model.goBack) { Image(systemName: "chevron.left") }.disabled(
          !model.canGoBack
        ).help("Back").accessibilityLabel("Back")
        Button(action: model.goForward) { Image(systemName: "chevron.right") }.disabled(
          !model.canGoForward
        ).help("Forward").accessibilityLabel("Forward")
      }
      HStack(spacing: 9) {
        Menu {
          Picker(
            "Match", selection: Binding(get: { model.textMatching }, set: model.selectTextMatching)
          ) {
            Text("Words & meaning").tag(VaultTextMatching.words)
            Text("Exact phrase").tag(VaultTextMatching.phrase)
            Text("Exact text (3+ characters)").tag(VaultTextMatching.literal)
          }
        } label: {
          Image(
            systemName: model.textMatching == .words ? "magnifyingglass" : "text.magnifyingglass")
        }.menuStyle(.borderlessButton).frame(width: 24).foregroundStyle(theme.secondary).help(
          "Choose how to match text"
        ).disabled(model.scope == .conversations)
        TextField(
          "Search your Vault", text: Binding(get: { model.searchText }, set: model.updateSearchText)
        ).textFieldStyle(.plain).focused(
          $searchFocused
        )
        .onChange(of: searchFocused) { _, focused in if focused { model.showLibrary() } }
        if !model.searchText.isEmpty {
          Button {
            model.updateSearchText("")
          } label: {
            Image(systemName: "xmark.circle.fill")
          }.foregroundStyle(theme.secondary).help("Clear search").accessibilityLabel("Clear search")
        } else {
          Text("⌘F").font(.caption).foregroundStyle(theme.secondary)
        }
      }
      .padding(.horizontal, 12).frame(height: 34)
      .background(theme.soft, in: RoundedRectangle(cornerRadius: 8))
      .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(theme.border, lineWidth: 0.5) }
      Button {
        model.showLibrary()
        model.showsFilters.toggle()
      } label: {
        HStack(spacing: 4) {
          Image(
            systemName: model.showsFilters
              ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
          if model.activeFilterCount > 0 {
            Text(model.activeFilterCount, format: .number).font(.caption.monospacedDigit())
          }
        }
      }.foregroundStyle(
        model.showsFilters || model.activeFilterCount > 0 ? theme.accent : theme.secondary
      )
      .help("Filter by type, date, app, companion, language and tags")
      .accessibilityLabel("Filter by type, date, app, companion, language and tags")
      .accessibilityValue(Text(model.activeFilterCount, format: .number))
      Button("New note", systemImage: "square.and.pencil") { Task { await model.newNote() } }
        .keyboardShortcut("n", modifiers: .command).disabled(model.isSaving)
      Button("Save link", systemImage: "link.badge.plus") { model.begin(.link) }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .foregroundStyle(theme.onAccent).background(
          theme.accent, in: RoundedRectangle(cornerRadius: 7))
      Button("Search") {
        model.showLibrary()
        searchFocused = true
      }.keyboardShortcut("f", modifiers: .command).hidden()
        .frame(width: 0)
    }.buttonStyle(.plain).font(.system(size: 13, weight: .medium))
      .padding(.horizontal, 18).frame(height: 56)
  }
}
