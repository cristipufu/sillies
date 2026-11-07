import SilliesCore
import SwiftUI

struct VaultConversationsView: View {
  @Environment(\.silliesTheme) private var theme
  @Bindable var model: VaultConversationsModel
  let isPresented: Bool
  @FocusState private var searchFocused: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Conversations").font(.system(size: 15, weight: .semibold)).padding(16)
      if let failure = model.openFailure {
        VaultNoticeArea { SessionFailureNotice(failure: failure) }
      }
      if model.isLoading { ProgressView("Searching…").controlSize(.small).padding(.horizontal, 16) }
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 12) {
          if model.query.isEmpty {
            ForEach(model.headers) { header in
              Button {
                model.reader.select(header.owner)
              } label: {
                row(name: header.owner.name, text: header.excerpt)
                  .background(
                    model.reader.owner == header.owner ? theme.accent.opacity(0.10) : .clear,
                    in: RoundedRectangle(cornerRadius: 7))
              }.buttonStyle(.plain)
            }
          } else {
            ForEach(model.results) { result in
              Button {
                model.reader.select(result.owner, messageID: result.id)
              } label: {
                row(name: result.owner.name, text: result.excerpt)
              }.buttonStyle(.plain)
            }
          }
          if !model.isLoading, model.loadFailure == nil, model.headers.isEmpty, model.query.isEmpty
          {
            Text("No conversations yet.").foregroundStyle(theme.secondary)
          }
          if !model.isLoading, model.loadFailure == nil, !model.query.isEmpty, model.results.isEmpty
          {
            Text("No matching messages.").foregroundStyle(theme.secondary)
          }
          if let failure = model.loadFailure {
            Text(failure).textSelection(.enabled).foregroundStyle(theme.danger)
            Button("Try again") { Task { await model.load() } }.buttonStyle(SoftButtonStyle())
          }
        }.padding(12)
      }.disabled(model.isOpening)
    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .task(id: isPresented ? model.searchIdentity : nil) {
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
      Label(name, systemImage: "bubble.left.and.bubble.right").font(
        .system(size: 13, weight: .semibold))
      Text(text).font(.system(size: 12)).foregroundStyle(theme.secondary).lineLimit(3)
    }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
  }
}
