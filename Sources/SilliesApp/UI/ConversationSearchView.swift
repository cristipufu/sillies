import SilliesChat
import SwiftUI

struct ConversationSearchView: View {
  @Environment(\.silliesTheme) private var theme
  let browser: ConversationBrowser
  let back: () -> Void
  @State private var query = ""
  @State private var date = Date()
  @FocusState private var searchFocused: Bool
  private static let searchDelay = Duration.milliseconds(250)
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      ChatPageHeader(title: String(localized: "Search conversation"), back: back)
      TextField("Search messages", text: $query).textFieldStyle(.roundedBorder)
        .focused($searchFocused).accessibilityLabel("Search messages")
      HStack {
        DatePicker("Jump to date", selection: $date, in: ...Date(), displayedComponents: .date)
          .datePickerStyle(.field).labelsHidden().accessibilityLabel("Jump to date")
        Spacer()
        Button("Go to date") {
          Task {
            if await browser.show(.onOrAfter(Calendar.current.startOfDay(for: date))) { back() }
          }
        }.buttonStyle(SoftButtonStyle()).disabled(browser.isLoading)
      }
      Divider()
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 12) {
          if isSearching {
            ProgressView("Searching messages…").frame(maxWidth: .infinity).padding(.top, 24)
          } else if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Label(
              "Find a word or jump to a day. Your full conversation stays on this Mac.",
              systemImage: "clock.arrow.circlepath"
            )
            .foregroundStyle(theme.secondary).padding(.vertical, 12)
          } else if browser.matches.isEmpty, browser.failure == nil {
            Text("No matching messages.").foregroundStyle(theme.secondary).padding(.vertical, 12)
          } else {
            ForEach(browser.matches) { match in
              Button {
                Task {
                  if await browser.show(.around(match.id)) { back() }
                }
              } label: {
                VStack(alignment: .leading, spacing: 4) {
                  HStack {
                    Text(
                      match.entry.message.role == .user
                        ? String(localized: "You") : match.owner.name
                    ).fontWeight(.semibold)
                    Spacer()
                    Text(match.entry.createdAt, style: .date)
                  }.font(.caption).foregroundStyle(theme.secondary)
                  Text(match.excerpt).lineLimit(4).frame(
                    maxWidth: .infinity, alignment: .leading)
                }.padding(10).background(theme.card, in: RoundedRectangle(cornerRadius: 12))
              }.buttonStyle(.plain).disabled(browser.isLoading)
            }
          }
          if let failure = browser.failure { Text(failure).font(.caption).textSelection(.enabled) }
        }
      }
    }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(theme.paper).foregroundStyle(theme.ink).tint(theme.accent)
      .onAppear { searchFocused = true }
      .onChange(of: query) { browser.cancelSearch() }
      .onDisappear {
        browser.cancelSearch()
        browser.cancelNavigation()
      }
      .task(id: query) {
        do { try await Task.sleep(for: Self.searchDelay) } catch { return }
        await browser.search(query)
      }
  }
  private var isSearching: Bool {
    !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && (browser.isSearching
        || browser.searchedQuery != query.trimmingCharacters(in: .whitespacesAndNewlines))
  }
}
