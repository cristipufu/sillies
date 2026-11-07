import AppKit
import SilliesCore
import SwiftUI

struct SessionVaultView: View {
  @Environment(\.silliesTheme) private var theme
  let vault: SessionVaultStore
  let conversations: VaultConversationsModel?
  @Bindable var model: SessionVaultModel
  @State private var compactNavigationVisible = false
  private static let expandedSidebarWidth: CGFloat = 1060

  var body: some View {
    GeometryReader { geometry in
      VStack(spacing: 0) {
        VaultWorkspaceToolbar(
          model: model.workspace,
          navigationVisible: geometry.size.width < Self.expandedSidebarWidth
            ? $compactNavigationVisible
            : Binding(
              get: { model.workspace.showsSidebar }, set: { model.workspace.showsSidebar = $0 })
        )
        .disabled(!model.isPresented)
        Divider().overlay(theme.border)
        if model.workspace.showsFilters, model.workspace.navigation.page == .library {
          VaultWorkspaceFilters(model: model.workspace, conversations: conversations)
        }
        HStack(spacing: 0) {
          if model.workspace.showsSidebar, geometry.size.width >= Self.expandedSidebarWidth {
            VaultWorkspaceSidebar(model: model.workspace)
              .frame(width: 196)
            Divider().overlay(theme.border)
          }
          content
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        VaultSearchPreparationView(
          model: model.workspace.searchPreparation, isPresented: model.isPresented)
        VaultWorkspaceStatus(vault: vault, model: model)
      }
      .overlay(alignment: .leading) {
        if compactNavigationVisible, geometry.size.width < Self.expandedSidebarWidth {
          HStack(spacing: 0) {
            VaultWorkspaceSidebar(model: model.workspace)
              .frame(width: 220).background(theme.paper)
            Rectangle().fill(theme.ink.opacity(0.10)).onTapGesture {
              compactNavigationVisible = false
            }
          }.padding(.top, 57)
        }
      }
    }
    .foregroundStyle(theme.ink).background(theme.paper)
    .task(id: showsCaptureLibrary ? model.workspace.searchIdentity : nil) {
      if showsCaptureLibrary { await model.workspace.refresh() }
    }
    .onChange(of: model.workspace.scope) { _, scope in
      if scope != .conversations { conversations?.reader.clear() }
      compactNavigationVisible = false
    }
    .onChange(of: model.workspace.searchText) { _, text in conversations?.query = text }
    .onChange(of: model.workspace.collectionID) { _, _ in conversations?.reader.clear() }
    .onChange(of: model.workspace.tag) { _, _ in conversations?.reader.clear() }
    .onChange(of: model.workspace.sourceFilter) { _, filter in
      conversations?.companionID = filter.companionID
      conversations?.reader.clear()
    }
    .onChange(of: model.workspace.navigation.transitionID) { _, _ in
      compactNavigationVisible = false
      if model.workspace.scope != .conversations { conversations?.reader.clear() }
    }
  }

  private var showsCaptureLibrary: Bool {
    model.isPresented && model.workspace.navigation.page == .library
      && model.workspace.scope != .conversations
  }

  @ViewBuilder private var content: some View {
    if model.workspace.navigation.page == .storage {
      VaultStorageView(vault: vault, actions: model)
    } else if let quotation = model.workspace.quotation {
      VaultQuoteDestinationView(passage: quotation, workspace: model.workspace)
    } else if model.workspace.composer != nil {
      VaultWorkspaceComposer(model: model.workspace)
    } else if model.workspace.scope == .conversations, let conversations {
      VaultConversationsView(model: conversations, isPresented: model.isPresented).frame(width: 290)
      Divider().overlay(theme.border)
      VaultConversationReader(model: conversations.reader) { conversations.open($0) }
    } else {
      VaultWorkspaceList(
        model: model.workspace, conversations: conversations,
        export: model.exportIDs, canExport: model.canExport
      ).frame(width: 290)
      Divider().overlay(theme.border)
      if let conversations, conversations.reader.owner != nil, model.workspace.scope == .all {
        VaultConversationReader(model: conversations.reader) { conversations.open($0) }
      } else if model.workspace.selectedID != nil {
        VaultDocumentView(
          vault: vault, model: model.workspace.document, actions: model, workspace: model.workspace
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        VaultDocumentPlaceholder(scope: model.workspace.scope) {
          Task { await model.workspace.newNote() }
        }
      }
    }
  }
}
