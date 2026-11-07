import SilliesCore
import SwiftUI

struct VaultConversationReader: View {
  @Environment(\.silliesTheme) private var theme
  @Bindable var model: VaultConversationReaderModel
  let continueChat: (ConversationOwner) -> Void
  var body: some View {
    if model.owner == nil {
      VStack(spacing: 14) {
        Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 28, weight: .light))
          .foregroundStyle(theme.accent.opacity(0.65))
        Text("Conversations").font(.system(size: 20, weight: .semibold, design: .rounded))
        Text("Choose a conversation to read it here.").font(.system(size: 13)).foregroundStyle(
          theme.secondary)
      }.multilineTextAlignment(.center).padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      conversation
    }
  }

  private var conversation: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let owner = model.owner {
        HStack {
          VStack(alignment: .leading, spacing: 6) {
            Text("Conversations").font(.caption).foregroundStyle(theme.secondary)
            Text(owner.name).font(.system(size: 24, weight: .bold, design: .rounded))
          }
          Spacer()
          Button("Continue chatting", systemImage: "bubble.left.and.bubble.right") {
            continueChat(owner)
          }
          .buttonStyle(SoftButtonStyle())
        }.padding(24)
      }
      Divider().overlay(theme.border)
      if let error = model.error {
        VaultNoticeArea {
          VStack(alignment: .leading, spacing: 8) {
            Text(error).textSelection(.enabled).foregroundStyle(theme.danger)
            Button("Try again") { Task { await model.retry() } }.buttonStyle(SoftButtonStyle())
              .disabled(model.isLoading)
          }.padding(16)
        }
      }
      if model.isLoading { ProgressView().controlSize(.small).padding(12) }
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 20) {
          ForEach(model.page?.entries ?? []) { entry in
            VStack(alignment: .leading, spacing: 6) {
              HStack {
                Text(
                  entry.message.role == .user ? String(localized: "You") : model.owner?.name ?? ""
                )
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.accent)
                Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                  .font(.caption2).foregroundStyle(theme.secondary)
              }
              Text(entry.message.text).font(.system(size: 13)).lineSpacing(4).textSelection(
                .enabled
              )
              .frame(maxWidth: .infinity, alignment: .leading)
            }.padding(14).background(theme.soft, in: RoundedRectangle(cornerRadius: 8))
          }
        }.padding(24)
      }
      if let page = model.page, page.hasOlder || page.hasNewer {
        HStack {
          if page.hasOlder, let first = page.entries.first {
            Button("Earlier messages") { Task { await model.move(.before(first.sequence)) } }
          }
          Spacer()
          if page.hasNewer, let last = page.entries.last {
            Button("Next messages") { Task { await model.move(.after(last.sequence)) } }
            Button("Latest") { Task { await model.move(.latest) } }
          }
        }.font(.caption).padding(16).disabled(model.isLoading)
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
