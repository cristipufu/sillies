import SilliesChat
import SilliesCore
import SwiftUI

struct ConversationMemoriesView: View {
  @Environment(\.silliesTheme) private var theme
  @Environment(\.dismiss) private var dismiss
  let model: ChatSession
  var openSettings: () -> Void = {}
  private enum Page { case pinned, learned, manage }
  private enum Layout {
    static let width: CGFloat = 380
    static let height: CGFloat = 500
    static let inset: CGFloat = 20
    static let sectionGap: CGFloat = 16
    static let rowGap: CGFloat = 12
    static let detailGap: CGFloat = 6
    static let corner: CGFloat = 14
    static let emptyInset: CGFloat = 24
  }
  @State private var selectedPage = Page.learned
  @State private var sourceFailure: String?
  private var browser: ChatMemoryBrowser { model.history.memories }
  var body: some View {
    VStack(alignment: .leading, spacing: Layout.sectionGap) {
      HStack {
        Text("Memories").font(.title2.bold())
        Spacer()
        Button("Done") { dismiss() }.buttonStyle(SoftButtonStyle()).disabled(
          model.personalFacts.isSaving)
      }
      Picker("Memories", selection: $selectedPage) {
        if model.personalFacts.isAvailable { Text("Pinned").tag(Page.pinned) }
        Text("Learned").tag(Page.learned)
        Text("Manage").tag(Page.manage)
      }.pickerStyle(.segmented).disabled(model.personalFacts.isSaving)
      if selectedPage == .pinned {
        ChatPersonalFactsView(model: model.personalFacts, companionName: model.companionName)
      } else if selectedPage == .manage {
        ConversationDataControlsView(
          model: model,
          openSettings: {
            dismiss()
            openSettings()
          })
      } else {
        learnedMemories
      }
    }.padding(Layout.inset).frame(width: Layout.width, height: Layout.height)
      .background(theme.paper).foregroundStyle(theme.ink).tint(theme.accent)
      .onDisappear {
        browser.invalidate()
        model.personalFacts.cancelEditing()
      }
      .onChange(of: browser.query) { sourceFailure = nil }
  }

  private var learnedMemories: some View {
    VStack(alignment: .leading, spacing: Layout.rowGap) {
      Text("Facts you shared with \(model.companionName). Review, edit or remove them here.")
        .font(.caption).foregroundStyle(theme.secondary)
      TextField(
        "Search memories", text: Binding(get: { browser.query }, set: { browser.query = $0 })
      )
      .textFieldStyle(.roundedBorder)
      ScrollView {
        LazyVStack(alignment: .leading, spacing: Layout.rowGap) {
          ForEach(browser.page.facts) { fact in
            VStack(alignment: .leading, spacing: Layout.detailGap) {
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
                    if await model.browser.show(.around(fact.sourceMessageID)) {
                      dismiss()
                    } else {
                      sourceFailure = model.browser.failure
                    }
                  }
                }
                Spacer()
                Button("Edit") { model.memoryEditor.edit(fact) }
                  .disabled(!model.canCompose || !model.memoryEditor.canEdit)
                Button("Forget", role: .destructive) { Task { await model.forgetMemory(fact) } }
                  .disabled(!model.canCompose)
              }.buttonStyle(SoftButtonStyle())
            }.padding(Layout.rowGap).background(
              theme.card, in: RoundedRectangle(cornerRadius: Layout.corner))
          }
          if browser.page.facts.isEmpty, !browser.isLoading, browser.failure == nil {
            Text(
              browser.query.isEmpty
                ? String(localized: "No memories yet.") : String(localized: "No matching memories.")
            )
            .foregroundStyle(theme.secondary).padding(.vertical, Layout.emptyInset)
          }
        }
      }.id(browser.pageRevision)
      if let failure = browser.failure {
        Text(failure).font(.caption).textSelection(.enabled)
        Button("Retry") { Task { await browser.show(.latest) } }
      }
      if let sourceFailure { Text(sourceFailure).font(.caption).foregroundStyle(theme.secondary) }
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
      Text(
        "Removing a memory keeps the original messages. Use Manage for separate deletion controls."
      )
      .font(.caption).foregroundStyle(theme.secondary)
    }.task(id: browser.searchIdentity) { await browser.show(.latest) }
  }
}
