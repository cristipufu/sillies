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
  @State private var showsReplyDetails = false
  private static let outgoingIndent: CGFloat = 36
  private static let outgoingHorizontalInset: CGFloat = 16
  private static let outgoingVerticalInset: CGFloat = 10
  private static let cornerRadius: CGFloat = 12
  private static let contentSpacing: CGFloat = 10
  var body: some View {
    let message = model.presentedMessage(original)
    let sources =
      model.browser.page == nil
      ? model.sourceCards(for: original) : model.browser.sourceCards(for: original)
    let fromUser = message.role == .user
    let text = message.text.isEmpty ? message.clarification?.question ?? "" : message.text
    return HStack(alignment: .bottom, spacing: 0) {
      if fromUser { Spacer(minLength: Self.outgoingIndent) }
      VStack(alignment: .leading, spacing: Self.contentSpacing) {
        if !text.isEmpty {
          ChatMessageText(
            text: text, color: theme.native(.ink),
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
        if let question = message.clarification, model.pendingClarification?.id == question.id {
          ChatClarificationView(question: question, model: model)
        }
        if let vault, !sources.isEmpty {
          ChatSourcesView(sources: sources, vault: vault).padding(.top, 6)
        }
        if !fromUser, message.contextInspection != nil || !message.exchanges.isEmpty {
          Button {
            showsReplyDetails = true
          } label: {
            Image(systemName: "info.circle").font(.callout).foregroundStyle(theme.secondary)
          }.buttonStyle(.plain).help("Reply details").accessibilityLabel("Reply details")
            .popover(isPresented: $showsReplyDetails) { ReplyDetailsView(message: message) }
        }
      }
      .padding(.horizontal, fromUser ? Self.outgoingHorizontalInset : 0)
      .padding(.vertical, fromUser ? Self.outgoingVerticalInset : 0)
      .background(
        fromUser ? theme.accent.opacity(0.12) : Color.clear,
        in: RoundedRectangle(cornerRadius: Self.cornerRadius)
      )
      .accessibilityElement(children: .contain)
      .accessibilityLabel(fromUser ? String(localized: "You") : model.companionName)
      .contextMenu {
        if model.memoryEditor.canRemember(message) {
          Button("Remember this…", systemImage: "sparkles") { model.memoryEditor.begin(message) }
            .disabled(!model.canCompose)
        }
        Button("Copy message", systemImage: "doc.on.doc") {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(text, forType: .string)
        }
      }
      if !fromUser { Spacer(minLength: 0) }
    }
  }
}
