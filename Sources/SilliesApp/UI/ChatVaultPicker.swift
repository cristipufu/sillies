import SilliesChat
import SilliesCore
import SwiftUI

struct ChatVaultPicker: View {
  @Environment(\.silliesTheme) private var theme
  let selection: ChatSelectedRecords
  let back: () -> Void
  @State private var model: ChatVaultPickerModel
  init(store: SessionVaultStore, selection: ChatSelectedRecords, back: @escaping () -> Void) {
    self.selection = selection
    self.back = back
    _model = State(initialValue: ChatVaultPickerModel(store: store))
  }
  private enum Layout {
    static let inset: CGFloat = 20
    static let gap: CGFloat = 12
    static let corner: CGFloat = 12
  }
  var body: some View {
    @Bindable var picker = model
    VStack(alignment: .leading, spacing: Layout.gap) {
      ChatPageHeader(title: String(localized: "Add from Vault"), back: back)
      Text("Choose a recording, screenshot or saved item to discuss.")
        .font(.caption).foregroundStyle(theme.secondary)
      TextField("Search Vault", text: $picker.query).textFieldStyle(.roundedBorder)
      ScrollView {
        LazyVStack(alignment: .leading, spacing: Layout.gap) {
          ForEach(model.records) { record in
            Button {
              if selection.add(record.id) { back() }
            } label: {
              HStack {
                Image(systemName: record.kind.symbolName).foregroundStyle(theme.accent)
                VStack(alignment: .leading, spacing: 4) {
                  Text(record.windowTitle ?? record.appName).lineLimit(2)
                  Text(record.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption).foregroundStyle(theme.secondary)
                }
                Spacer()
                Image(
                  systemName: selection.selection.ids.contains(record.id)
                    ? "checkmark.circle.fill" : "plus.circle")
              }.padding(Layout.gap).background(
                theme.card, in: RoundedRectangle(cornerRadius: Layout.corner))
            }.buttonStyle(.plain).disabled(
              !selection.canAdd || selection.selection.ids.contains(record.id))
          }
          if model.records.isEmpty, !model.isLoading {
            Text("No matching sessions").foregroundStyle(theme.secondary)
          }
        }
      }
      if model.isLoading { ProgressView().controlSize(.small) }
      if let failure = model.failure { Text(failure).font(.caption).textSelection(.enabled) }
      Text("Up to three items. Remove an item from Chat to stop including it in future replies.")
        .font(.caption).foregroundStyle(theme.secondary)
    }.padding(Layout.inset).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(theme.paper).foregroundStyle(theme.ink).tint(theme.accent)
      .task(id: model.query) { await model.search() }
  }
}
