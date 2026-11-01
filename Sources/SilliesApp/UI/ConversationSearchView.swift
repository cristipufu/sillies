import SilliesChat
import SwiftUI

struct ConversationSearchView: View {
  @Environment(\.silliesTheme) private var theme
  @Environment(\.dismiss) private var dismiss
  let browser: ConversationBrowser
  @State private var query = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("Search conversation").font(.headline)
        Spacer()
        Button("Done") { dismiss() }.buttonStyle(SoftButtonStyle())
      }
      TextField("Search messages", text: $query).textFieldStyle(.roundedBorder)
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 12) {
          ForEach(browser.matches) { match in
            Button {
              Task {
                await browser.show(.around(match.id))
                dismiss()
              }
            } label: {
              VStack(alignment: .leading, spacing: 4) {
                Text(match.entry.createdAt, style: .date).font(.caption).foregroundStyle(
                  theme.secondary)
                Text(match.entry.message.text).lineLimit(4).frame(
                  maxWidth: .infinity, alignment: .leading)
              }.padding(10).background(theme.card, in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain)
          }
          if let failure = browser.failure { Text(failure).textSelection(.enabled) }
          if browser.matches.isEmpty, !query.isEmpty {
            Text("No matching messages.").foregroundStyle(theme.secondary)
          }
        }
      }
    }.padding(20).frame(width: 360, height: 420)
      .background(theme.paper).foregroundStyle(theme.ink).tint(theme.accent)
      .task(id: query) {
        do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
        await browser.search(query)
      }
  }
}
