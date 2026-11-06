import SilliesChat
import SwiftUI

struct ChatContextStrip: View {
  @Environment(\.silliesTheme) private var theme
  let selection: ChatSelectedRecords
  let openRecord: (UUID) -> Void
  private enum Layout {
    static let gap: CGFloat = 6
    static let inset: CGFloat = 8
    static let corner: CGFloat = 10
    static let horizontalInset: CGFloat = 16
  }
  var body: some View {
    VStack(alignment: .leading, spacing: Layout.gap) {
      ForEach(selection.selection.ids, id: \.self) { id in
        let record = selection.records.first { $0.id == id }
        HStack(spacing: Layout.gap) {
          Image(systemName: record?.isAvailable == false ? "exclamationmark.circle" : "paperclip")
            .foregroundStyle(record?.isAvailable == false ? theme.warning : theme.accent)
          Button {
            openRecord(id)
          } label: {
            Text(
              record?.title
                ?? (selection.failure == nil
                  ? String(localized: "Loading Vault item…")
                  : String(localized: "Unavailable Vault item"))
            )
            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
          }.buttonStyle(.plain).disabled(record?.isAvailable != true)
          Button {
            selection.remove(id)
          } label: {
            Image(systemName: "xmark")
          }
          .buttonStyle(.plain).disabled(!selection.canChange())
          .accessibilityLabel("Remove selected item").help("Remove selected item")
        }.font(.caption).padding(Layout.inset)
          .background(theme.card, in: RoundedRectangle(cornerRadius: Layout.corner))
      }
      if let failure = selection.failure {
        Text(failure).font(.caption).foregroundStyle(theme.warning).textSelection(.enabled)
      }
    }.padding(.horizontal, Layout.horizontalInset)
      .help(
        "Selected items are included in future replies until removed. Earlier messages may still quote them."
      )
  }
}
