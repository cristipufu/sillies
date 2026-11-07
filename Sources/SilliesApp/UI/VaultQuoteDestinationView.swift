import SilliesCore
import SwiftUI

struct VaultQuoteDestinationView: View {
  @Environment(\.silliesTheme) private var theme
  @State private var model: VaultQuoteDestinationModel
  let workspace: VaultWorkspaceModel
  @State private var saveTask: Task<Void, Never>?
  init(passage: VaultQuotedPassage, workspace: VaultWorkspaceModel) {
    self.workspace = workspace
    _model = State(initialValue: .init(vault: workspace.vault, passage: passage))
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Button("Back to document", systemImage: "chevron.left") { workspace.showLibrary() }
        .buttonStyle(.plain).disabled(model.isSaving)
      Text("Keep this passage").font(.system(size: 24, weight: .bold, design: .rounded))
      Text(model.passage.text).font(.system(size: 14)).foregroundStyle(theme.secondary).lineLimit(4)
      Text("The quotation includes a link to its source. Choose where to add it to My notes.")
        .font(.callout).foregroundStyle(theme.secondary)
      Button("Create a new note", systemImage: "square.and.pencil") { save(to: nil) }
      TextField("Find a note or capture", text: $model.query).textFieldStyle(.roundedBorder)
      if let error = model.error {
        Text(error).font(.caption).foregroundStyle(theme.danger).textSelection(.enabled)
      }
      if model.isSaving { ProgressView().controlSize(.small) }
      List(model.candidates) { header in
        Button {
          save(to: header.id)
        } label: {
          Label(header.title, systemImage: header.symbol).padding(.vertical, 6).frame(
            maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(.plain)
      }.listStyle(.plain).scrollContentBackground(.hidden).disabled(model.isSaving)
    }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
      .task(id: model.query) { await model.search() }
      .onDisappear { saveTask?.cancel() }
  }
  private func save(to id: UUID?) {
    guard saveTask == nil else { return }
    saveTask = Task {
      defer { saveTask = nil }
      await workspace.document.flush()
      guard workspace.document.canNavigate, !Task.isCancelled else { return }
      guard let location = await model.save(to: id), !Task.isCancelled else { return }
      workspace.visit(location)
      await workspace.refresh()
    }
  }
}
