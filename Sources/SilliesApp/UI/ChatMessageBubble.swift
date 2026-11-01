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
    let fromUser = message.role == .user
    return HStack(alignment: .bottom, spacing: 0) {
      if fromUser { Spacer(minLength: 52) }
      VStack(alignment: .leading, spacing: 5) {
        Text(fromUser ? String(localized: "You") : model.companionName)
          .font(.system(size: 11, weight: .semibold, design: .rounded))
          .foregroundStyle(fromUser ? theme.onAccent.opacity(0.8) : theme.secondary)
        ChatMessageText(
          text: message.text, color: theme.native(fromUser ? .onAccent : .ink),
          selectionChanged: selectionChanged)
        if message.completion == .interrupted {
          Text("Stopped").font(.caption2).foregroundStyle(theme.secondary)
        }
        if let vault, !message.sources.isEmpty {
          ChatSourcesView(sources: message.sources, vault: vault).padding(.top, 6)
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
        Button("Copy message", systemImage: "doc.on.doc") {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(message.text, forType: .string)
        }
      }
      if !fromUser { Spacer(minLength: 52) }
    }
  }
}
