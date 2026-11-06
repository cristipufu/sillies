import SilliesCore
import SwiftUI

struct VaultConversationsView: View {
  @Environment(\.silliesTheme) private var theme
  @Bindable var model: VaultConversationsModel
  let isPresented: Bool
  @FocusState private var searchFocused: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Conversations").font(.system(.largeTitle, design: .rounded).bold())
      TextField("Search messages", text: $model.query).textFieldStyle(.roundedBorder)
        .focused($searchFocused)
      if let failure = model.openFailure { SessionFailureNotice(failure: failure) }
      if model.isLoading { ProgressView("Searching…").controlSize(.small) }
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 12) {
          if model.query.isEmpty {
            ForEach(model.headers) { header in
              Button {
                model.open(header.owner)
              } label: {
                row(name: header.owner.name, text: header.excerpt)
              }.buttonStyle(.plain)
            }
          } else {
            ForEach(model.results) { result in
              Button {
                model.open(result.owner, messageID: result.id)
              } label: {
                row(name: result.owner.name, text: result.entry.message.text)
              }.buttonStyle(.plain)
            }
          }
          if !model.isLoading, model.headers.isEmpty, model.query.isEmpty {
            Text("No conversations yet.").foregroundStyle(theme.secondary)
          }
          if !model.isLoading, !model.query.isEmpty, model.results.isEmpty {
            Text("No matching messages.").foregroundStyle(theme.secondary)
          }
          if let failure = model.loadFailure { Text(failure).textSelection(.enabled) }
        }
      }.disabled(model.isOpening)
    }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .task(id: isPresented ? model.query : nil) {
        if isPresented { await model.load() }
      }
      .onChange(of: isPresented) { _, visible in
        if !visible {
          searchFocused = false
          model.stop()
        }
      }
      .onDisappear { model.stop() }
  }
  private func row(name: String, text: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Label(name, systemImage: "bubble.left.and.bubble.right").font(.headline)
      Text(text).font(.callout).foregroundStyle(theme.secondary).lineLimit(3)
    }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
      .background(theme.card, in: RoundedRectangle(cornerRadius: 18))
  }
}
