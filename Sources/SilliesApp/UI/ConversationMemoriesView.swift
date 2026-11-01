import SilliesChat
import SwiftUI

struct ConversationMemoriesView: View {
  @Environment(\.silliesTheme) private var theme
  @Environment(\.dismiss) private var dismiss
  let model: ChatSession
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("Memories").font(.title2.bold())
        Spacer()
        Button("Done") { dismiss() }.buttonStyle(SoftButtonStyle())
      }
      Text(
        "Facts you shared with \(model.companionName). You can correct a fact in conversation or remove it here."
      )
      .font(.callout).foregroundStyle(theme.secondary)
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 12) {
          ForEach(model.history.rememberedFacts) { fact in
            VStack(alignment: .leading, spacing: 6) {
              Text(fact.value).font(.body).textSelection(.enabled)
              Text(fact.sourceQuote).font(.caption).foregroundStyle(theme.secondary).textSelection(
                .enabled)
              HStack {
                Button("Show message") {
                  Task {
                    await model.browser.show(.around(fact.sourceMessageID))
                    dismiss()
                  }
                }
                Spacer()
                Button("Forget", role: .destructive) { Task { await model.forgetMemory(fact) } }
                  .disabled(!model.canCompose)
              }.buttonStyle(SoftButtonStyle())
            }.padding(12).background(theme.card, in: RoundedRectangle(cornerRadius: 14))
          }
          if model.history.rememberedFacts.isEmpty {
            Text("No memories yet.").foregroundStyle(theme.secondary).padding(.vertical, 24)
          }
        }
      }
      Text("Removing a memory keeps the original messages. Clear the conversation to delete both.")
        .font(.caption).foregroundStyle(theme.secondary)
    }.padding(20).frame(width: 360, height: 420)
      .background(theme.paper).foregroundStyle(theme.ink).tint(theme.accent)
  }
}
