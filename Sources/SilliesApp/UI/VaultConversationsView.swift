import SilliesCore
import SwiftUI

struct VaultConversationPresentation {
  let repository: any ConversationRepository
  let open: (ConversationOwner, UUID?) -> Void
}

struct VaultConversationsView: View {
  @Environment(\.silliesTheme) private var theme
  let presentation: VaultConversationPresentation
  @State private var headers: [ConversationHeader] = []
  @State private var results: [ConversationSearchMatch] = []
  @State private var query = ""
  @State private var failure: String?
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Conversations").font(.system(.largeTitle, design: .rounded).bold())
      TextField("Search messages", text: $query).textFieldStyle(.roundedBorder)
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 12) {
          if query.isEmpty {
            ForEach(headers) { header in
              Button {
                presentation.open(header.owner, nil)
              } label: {
                row(name: header.owner.name, text: header.excerpt)
              }.buttonStyle(.plain)
            }
          } else {
            ForEach(results) { result in
              Button {
                presentation.open(result.owner, result.id)
              } label: {
                row(name: result.owner.name, text: result.entry.message.text)
              }.buttonStyle(.plain)
            }
          }
          if headers.isEmpty, query.isEmpty {
            Text("No conversations yet.").foregroundStyle(theme.secondary)
          }
          if let failure { Text(failure).textSelection(.enabled) }
        }
      }
    }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .task(id: query) { await load() }
  }
  private func row(name: String, text: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Label(name, systemImage: "bubble.left.and.bubble.right").font(.headline)
      Text(text).font(.callout).foregroundStyle(theme.secondary).lineLimit(3)
    }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
      .background(theme.card, in: RoundedRectangle(cornerRadius: 18))
  }
  private func load() async {
    do {
      if query.isEmpty {
        let loaded = try await presentation.repository.conversations()
        guard !Task.isCancelled else { return }
        headers = loaded
      } else {
        try await Task.sleep(for: .milliseconds(250))
        let loaded = try await presentation.repository.search(.init(query: query))
        guard !Task.isCancelled else { return }
        results = loaded
      }
      failure = nil
    } catch {
      guard !Task.isCancelled else { return }
      failure = error.localizedDescription
      fputs("Conversation list failed: \(error)\n", stderr)
    }
  }
}
