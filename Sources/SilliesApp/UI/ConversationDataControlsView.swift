import SilliesChat
import SilliesCore
import SwiftUI

struct ConversationDataControlsView: View {
  @Environment(\.silliesTheme) private var theme
  let model: ChatSession
  let openSettings: () -> Void
  @State private var pending: ConversationDataRemoval?
  private enum Layout {
    static let gap: CGFloat = 14
    static let inset: CGFloat = 12
    static let corner: CGFloat = 12
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Layout.gap) {
        ForEach(ConversationDataRemoval.allCases, id: \.self) { removal in
          VStack(alignment: .leading, spacing: Layout.gap) {
            Text(removal.detail).font(.caption).foregroundStyle(theme.secondary)
              .fixedSize(horizontal: false, vertical: true)
            Button(removal.title, role: .destructive) { pending = removal }
              .buttonStyle(SoftButtonStyle()).disabled(!model.canCompose)
          }.padding(Layout.inset).frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.card, in: RoundedRectangle(cornerRadius: Layout.corner))
        }
        Text(
          "Pinned facts stay until you unpin them. Past messages may still contain facts you forget."
        )
        .font(.caption).foregroundStyle(theme.secondary).fixedSize(
          horizontal: false, vertical: true)
        Button("Companion settings…", action: openSettings).buttonStyle(SoftButtonStyle())
        Text(
          "Reset personality, language and voice in companion settings. This keeps messages and memories."
        )
        .font(.caption).foregroundStyle(theme.secondary).fixedSize(
          horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }.confirmationDialog(
      pending?.title ?? "",
      isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
    ) {
      if let removal = pending {
        Button(removal.title, role: .destructive) {
          Task { await model.removeConversationData(removal) }
        }
      }
    } message: {
      Text(pending?.detail ?? "")
    }
  }
}

extension ConversationDataRemoval {
  fileprivate var title: String {
    switch self {
    case .messages: String(localized: "Delete messages only…")
    case .learnedMemories: String(localized: "Forget learned memories…")
    case .messagesAndMemories: String(localized: "Delete messages and learned memories…")
    }
  }
  fileprivate var detail: String {
    switch self {
    case .messages:
      String(
        localized:
          "Delete this companion’s messages and draft. Keep learned memories, pinned facts and preferences."
      )
    case .learnedMemories:
      String(
        localized:
          "Remove this companion’s learned memories and generated notes. Keep the original messages searchable."
      )
    case .messagesAndMemories:
      String(
        localized:
          "Delete this companion’s messages, draft and learned memories. Keep pinned facts and preferences."
      )
    }
  }
}
