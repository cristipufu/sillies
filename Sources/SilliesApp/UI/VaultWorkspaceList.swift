import SilliesCore
import SwiftUI

struct VaultWorkspaceList: View {
  @Environment(\.silliesTheme) private var theme
  @Bindable var model: VaultWorkspaceModel
  var conversations: VaultConversationsModel?
  let export: ([UUID]) -> Void
  let canExport: Bool
  @State private var confirmsEmptyTrash = false
  private var conversationSearch: VaultConversationsModel.SearchIdentity? {
    guard model.isPresented, model.includesConversations else { return nil }
    return .init(query: model.searchText, companionID: model.sourceFilter.companionID)
  }
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text(
          model.collectionID.flatMap { id in model.collections.first { $0.id == id }?.name }
            ?? model.scope.title
        )
        .font(.system(size: 15, weight: .semibold)).lineLimit(1)
        Spacer()
        if model.isLoading || model.isOpening { ProgressView().controlSize(.small) }
        Menu {
          Picker("Sort", selection: $model.ordering) {
            Text("Newest first").tag(VaultWorkspaceQuery.Ordering.newest)
            Text("Oldest first").tag(VaultWorkspaceQuery.Ordering.oldest)
            Text("Recently edited").tag(VaultWorkspaceQuery.Ordering.modified)
            if !model.searchText.isEmpty {
              Text("Best match").tag(VaultWorkspaceQuery.Ordering.relevance)
            }
          }
        } label: {
          HStack(spacing: 4) {
            Text(model.ordering.title).font(.caption)
            Image(systemName: "arrow.up.arrow.down")
          }
        }.menuStyle(.borderlessButton).fixedSize().foregroundStyle(theme.secondary)
      }.padding(16)
      VaultNoticeArea {
        VStack(alignment: .leading, spacing: 0) {
          VaultQueryProgress(model: model)
          if let error = model.error {
            Text(error).font(.caption).textSelection(.enabled).foregroundStyle(theme.danger)
              .padding(.horizontal, 16)
            Button("Try again") { Task { await model.refresh() } }.padding(8)
          }
        }
      }
      if model.scope == .trash, !model.records.isEmpty {
        HStack {
          Text("Restore items or delete them permanently.").font(.caption).foregroundStyle(
            theme.secondary)
          Spacer()
          Button("Empty Trash…") { confirmsEmptyTrash = true }.disabled(model.isSaving)
        }.padding(.horizontal, 16).padding(.bottom, 8)
      }
      if model.records.isEmpty && model.related.isEmpty
        && (!model.includesConversations || conversations?.results.isEmpty != false)
        && !model.isLoading && !model.isFindingRelated && model.error == nil
      {
        VaultEmptyState(model: model)
      } else {
        List(selection: $model.selectedIDs) {
          if model.ordering == .relevance {
            ForEach(model.records) { header in row(header).tag(header.id) }
          } else {
            ForEach(VaultDateGroup.make(model.records, ordering: model.ordering)) { group in
              Section(group.title) {
                ForEach(group.records) { header in row(header).tag(header.id) }
              }
            }
          }
          if !model.related.isEmpty {
            Section("Related by meaning") {
              ForEach(model.related) { header in row(header).tag(header.id) }
            }
          }
          if model.includesConversations, let conversations, !conversations.results.isEmpty {
            Section("Conversations") {
              ForEach(conversations.results) { match in
                Button {
                  model.selectedIDs = []
                  conversations.reader.select(match.owner, messageID: match.id)
                } label: {
                  VStack(alignment: .leading, spacing: 6) {
                    Label(match.owner.name, systemImage: "bubble.left.and.bubble.right").font(
                      .system(size: 13, weight: .semibold))
                    Text(match.excerpt).font(.system(size: 12)).foregroundStyle(theme.secondary)
                      .lineLimit(3)
                  }.padding(.vertical, 9)
                }.buttonStyle(.plain)
              }
            }
          }
        }.listStyle(.plain).scrollContentBackground(.hidden)
          .onChange(of: model.selectedIDs) { _, ids in
            if ids.count == 1, let id = ids.first {
              conversations?.reader.clear()
              model.select(id)
            }
          }
      }
      if model.selectedIDs.count > 1 || model.canReturnToPreviousPage || model.hasMore {
        Divider().overlay(theme.border)
        HStack {
          if model.selectedIDs.count > 1 {
            Text("\(model.selectedIDs.count) selected").font(.caption)
            Spacer()
            Menu {
              Button("Export Markdown & attachments…") { export(Array(model.selectedIDs)) }
                .disabled(
                  !canExport)
              Button("Star") { Task { await model.editSelection(.star) } }
              Button("Remove star") { Task { await model.editSelection(.unstar) } }
              Menu("Add to collection") {
                ForEach(model.collections) { collection in
                  Button(collection.name) {
                    Task { await model.editSelection(.addToCollection(collection.id)) }
                  }
                }
              }
              Button(
                model.scope == .trash
                  ? String(localized: "Restore") : String(localized: "Move to Trash")
              ) {
                Task { await model.editSelection(model.scope == .trash ? .restore : .moveToTrash) }
              }
            } label: {
              Image(systemName: "ellipsis.circle")
            }.menuStyle(.borderlessButton).frame(width: 24).disabled(!model.canEditSelection)
          } else {
            Text("Page \(model.pageNumber + 1)").font(.caption).foregroundStyle(theme.secondary)
            Spacer()
            Button {
              Task { await model.previousPage() }
            } label: {
              Image(systemName: "chevron.left")
            }.disabled(!model.canReturnToPreviousPage || model.isLoading).help("Previous page")
            Button {
              Task { await model.nextPage() }
            } label: {
              Image(systemName: "chevron.right")
            }.disabled(!model.hasMore || model.isLoading).help("Next page")
          }
        }.buttonStyle(.plain).padding(14)
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(
      theme.paper
    )
    .confirmationDialog(
      "Permanently delete all items in Trash?", isPresented: $confirmsEmptyTrash
    ) {
      Button("Empty Trash", role: .destructive) { Task { await model.emptyTrash() } }
    } message: {
      Text("Their notes, transcripts and saved files will be removed. This cannot be undone.")
    }
    .task(id: conversationSearch) {
      if let conversationSearch {
        conversations?.query = conversationSearch.query
        conversations?.companionID = conversationSearch.companionID
        await conversations?.load()
      }
    }
  }

  private func row(_ header: VaultDocumentHeader) -> some View {
    VaultDocumentListRow(header: header, workspace: model)
  }
}
