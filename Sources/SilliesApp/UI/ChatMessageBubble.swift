import AppKit
import SilliesChat
import SilliesCore
import SwiftUI

/// Each row observes its current text; token batches never copy the complete chat history.
struct ChatMessageBubble: View {
  @Environment(\.silliesTheme) private var theme
  let model: ChatSession
  let original: ChatMessage
  let vault: ChatVaultPresentation?
  let selectionChanged: (Bool) -> Void
  var body: some View {
    let message = model.presentedMessage(original)
    let sources =
      model.browser.page == nil
      ? model.sourceCards(for: original) : model.browser.sourceCards(for: original)
    let fromUser = message.role == .user
    return HStack(alignment: .bottom, spacing: 0) {
      if fromUser { Spacer(minLength: 52) }
      VStack(alignment: .leading, spacing: 5) {
        Text(fromUser ? String(localized: "You") : model.companionName)
          .font(.system(size: 11, weight: .semibold, design: .rounded))
          .foregroundStyle(fromUser ? theme.onAccent.opacity(0.8) : theme.secondary)
        if !message.text.isEmpty {
          ChatMessageText(
            text: message.text, color: theme.native(fromUser ? .onAccent : .ink),
            selectionChanged: selectionChanged)
        }
        ForEach(model.history.memoryReceipts.filter { $0.saved.sourceMessageID == message.id }) {
          receipt in
          HStack(alignment: .top, spacing: 6) {
            Image(systemName: "sparkles")
            VStack(alignment: .leading, spacing: 2) {
              Text("Saved memory").fontWeight(.semibold)
              Text(receipt.saved.value).lineLimit(2)
            }
            Button("Undo") { Task { await model.undoMemory(receipt) } }.disabled(!model.canCompose)
          }.font(.caption).padding(8)
            .background(theme.card, in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(theme.ink)
            .accessibilityLabel(Text("Saved memory: \(receipt.saved.value)"))
        }
        if message.completion == .interrupted {
          Text("Stopped").font(.caption2).foregroundStyle(theme.secondary)
        }
        if let vault, !sources.isEmpty {
          ChatSourcesView(sources: sources, vault: vault).padding(.top, 6)
        }
      }
      .padding(.horizontal, 14).padding(.vertical, 11)
      .background(
        fromUser ? theme.accentFill : theme.card,
        in: RoundedRectangle(cornerRadius: 18)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 18).strokeBorder(
          fromUser ? Color.clear : theme.border)
      )
      .contextMenu {
        if model.memoryEditor.canRemember(message) {
          Button("Remember this…", systemImage: "sparkles") { model.memoryEditor.begin(message) }
            .disabled(!model.canCompose)
        }
        Button("Copy message", systemImage: "doc.on.doc") {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(message.text, forType: .string)
        }
      }
      if !fromUser { Spacer(minLength: 52) }
    }
  }
}
