import SilliesChat
import SwiftUI

struct ConversationMemoriesView: View {
  @Environment(\.silliesTheme) private var theme
  @Environment(\.dismiss) private var dismiss
  let model: ChatSession
  private var browser: ChatMemoryBrowser { model.history.memories }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("Memories").font(.title2.bold())
        Spacer()
        Button("Done") { dismiss() }.buttonStyle(SoftButtonStyle())
      }
      Text("Facts you shared with \(model.companionName). Review, edit or remove them here.")
        .font(.callout).foregroundStyle(theme.secondary)
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 12) {
          ForEach(browser.page.facts) { fact in
            VStack(alignment: .leading, spacing: 6) {
              Text(fact.value).font(.body).textSelection(.enabled)
              if fact.source.attribution == .userCorrection {
                Label("Edited by you", systemImage: "pencil").font(.caption)
                  .foregroundStyle(theme.secondary)
              }
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
                Button("Edit") { model.memoryEditor.edit(fact) }
                  .disabled(!model.canCompose || !model.memoryEditor.canEdit)
                Button("Forget", role: .destructive) { Task { await model.forgetMemory(fact) } }
                  .disabled(!model.canCompose)
              }.buttonStyle(SoftButtonStyle())
            }.padding(12).background(theme.card, in: RoundedRectangle(cornerRadius: 14))
          }
          if browser.page.facts.isEmpty, !browser.isLoading, browser.failure == nil {
            Text("No memories yet.").foregroundStyle(theme.secondary).padding(.vertical, 24)
          }
        }
      }.id(browser.pageRevision)
      if let failure = browser.failure {
        Text(failure).font(.caption).textSelection(.enabled)
        Button("Retry") { Task { await browser.show(.latest) } }
      }
      HStack {
        if let previous = browser.page.previous {
          Button("Newer") { Task { await browser.show(.after(previous)) } }
        }
        Spacer()
        if browser.isLoading { ProgressView().controlSize(.small) }
        if let next = browser.page.next {
          Button("Older") { Task { await browser.show(.before(next)) } }
        }
      }.buttonStyle(SoftButtonStyle()).disabled(browser.isLoading)
      Text("Removing a memory keeps the original messages. Clear the conversation to delete both.")
        .font(.caption).foregroundStyle(theme.secondary)
    }.padding(20).frame(width: 360, height: 420)
      .background(theme.paper).foregroundStyle(theme.ink).tint(theme.accent)
      .onDisappear { browser.invalidate() }
  }
}
