import AppKit
import SilliesChat
import SilliesCore
import SwiftUI

struct ChatMessagesView: View {
  @Environment(\.silliesTheme) private var theme
  let model: ChatSession
  let motion: ChatPresentationMotion
  var vault: ChatVaultPresentation? = nil
  var focusComposer: () -> Void = {}
  @Environment(\.chatReadingSize) private var readingSize
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  private var reduceMotion: Bool { systemReduceMotion || motion == .reduced }
  private enum ReadingPosition {
    case latest, reading, question
  }
  @State private var readingPosition = ReadingPosition.latest
  private var followsLatest: Bool {
    if case .latest = readingPosition { true } else { false }
  }
  @State private var nearBottom = true
  @State private var selectedMessages: Set<UUID> = []
  @State private var visibleMessages: Set<UUID> = []
  @State private var selectionReset: UUID?
  private static let bottomID = "latest-chat-message"
  private static let bottomThreshold: CGFloat = 48
  private static let messageSpacing: CGFloat = 16
  private static let contentInset: CGFloat = 16
  private static let welcomeSpacing: CGFloat = 10
  private static let welcomeTitleSize: CGFloat = 20
  private static let welcomeInset: CGFloat = 8
  private var navigation: ConversationNavigation {
    .init(
      latestMessageID: model.messages.last?.id, hasEarlierMessages: model.hasEarlierMessages,
      page: model.browser.page, nearBottom: nearBottom)
  }

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: Self.messageSpacing) {
          if model.messages.isEmpty { welcome }
          if model.browser.page?.entries.isEmpty == true {
            Text("No messages from this date onward.").font(.callout).foregroundStyle(
              theme.secondary)
          }
          if let failure = model.browser.failure {
            Text(failure).font(.caption).foregroundStyle(theme.secondary).textSelection(.enabled)
          }
          if let page = model.browser.page {
            if page.hasOlder || page.hasNewer {
              HStack {
                if page.hasOlder, let first = page.entries.first {
                  Button("Older") { Task { await model.browser.show(.before(first.sequence)) } }
                }
                Spacer()
                if page.hasNewer, let last = page.entries.last {
                  Button("Newer") { Task { await model.browser.show(.after(last.sequence)) } }
                }
              }.buttonStyle(SoftButtonStyle()).disabled(model.browser.isLoading)
            }
          } else if navigation.showsEarlier, let first = model.messages.first {
            Button("Earlier messages") {
              Task { await model.browser.show(.beforeMessage(first.id)) }
            }
            .buttonStyle(SoftButtonStyle()).frame(maxWidth: .infinity)
            .disabled(model.browser.isLoading)
          }
          ForEach(model.browser.page?.entries.map(\.message) ?? model.messages) { message in
            bubble(message).id(message.id)
              .onScrollVisibilityChange(threshold: 0.5) { visible in
                if visible {
                  visibleMessages.insert(message.id)
                } else {
                  visibleMessages.remove(message.id)
                }
                if !followsLatest, model.browser.page == nil,
                  let first = model.messages.first(where: { visibleMessages.contains($0.id) })
                {
                  model.browser.rememberPosition(first.id)
                }
              }
              .transition(
                .asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity))
          }
          if model.isWorking, model.browser.page == nil {
            Label(model.status, systemImage: "ellipsis.bubble.fill")
              .font(.system(size: readingSize.points)).foregroundStyle(theme.secondary)
          }
          Color.clear.frame(height: 1).id(Self.bottomID)
        }.padding(Self.contentInset)
          .environment(\.chatSelectionReset, selectionReset)
          .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.messages.count)
      }
      .defaultScrollAnchor(
        model.messages.isEmpty || model.pendingClarification != nil ? .top : .bottom,
        for: .initialOffset
      )
      .defaultScrollAnchor(.top, for: .alignment)
      .onScrollGeometryChange(for: Viewport.self) { geometry in
        Viewport(
          contentHeight: geometry.contentSize.height,
          nearBottom: geometry.contentSize.height - geometry.visibleRect.maxY
            <= Self.bottomThreshold)
      } action: { previous, current in
        nearBottom = current.nearBottom
        if current.contentHeight != previous.contentHeight, !model.messages.isEmpty, followsLatest,
          selectedMessages.isEmpty,
          model.browser.page == nil
        {
          proxy.scrollTo(Self.bottomID, anchor: .bottom)
        }
      }
      .onAppear {
        if let id = model.browser.focusedMessageID ?? model.history.checkpoint.readingMessageID {
          readingPosition = .reading
          if model.messages.contains(where: { $0.id == id }) || model.browser.page != nil {
            proxy.scrollTo(id, anchor: .top)
          } else {
            Task { await model.browser.show(.around(id)) }
          }
        } else {
          showPendingQuestion(using: proxy)
        }
      }
      .onChange(of: model.pendingClarification?.id) { _, id in
        if id == nil, case .question = readingPosition {
          readingPosition = selectedMessages.isEmpty ? .latest : .reading
          if followsLatest, model.browser.page == nil {
            proxy.scrollTo(Self.bottomID, anchor: .bottom)
          }
          return
        }
        guard id != nil, followsLatest, selectedMessages.isEmpty, model.browser.page == nil else {
          return
        }
        showPendingQuestion(using: proxy)
      }
      .onChange(of: model.browser.focusedMessageID) { _, id in
        guard let id else { return }
        readingPosition = .reading
        proxy.scrollTo(id, anchor: .top)
        model.browser.rememberPosition(id)
      }
      .onScrollPhaseChange { _, phase in
        if phase == .interacting { readingPosition = .reading }
        if phase == .idle, nearBottom, model.browser.page == nil {
          readingPosition = .latest
          model.browser.rememberPosition(nil)
        }
      }
      .overlay(alignment: .bottom) {
        if navigation.showsLatest {
          Button("Latest", systemImage: "arrow.down") {
            model.browser.showLatest()
            readingPosition = .latest
            selectedMessages.removeAll()
            selectionReset = UUID()
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
              proxy.scrollTo(Self.bottomID, anchor: .bottom)
            }
          }.buttonStyle(AccentButtonStyle()).clipShape(Capsule()).padding(12)
        }
      }
    }
  }

  private struct Viewport: Equatable {
    let contentHeight: CGFloat
    let nearBottom: Bool
  }

  private func showPendingQuestion(using proxy: ScrollViewProxy) {
    guard model.pendingClarification != nil, model.browser.page == nil,
      let id = model.messages.last?.id
    else { return }
    readingPosition = .question
    proxy.scrollTo(id, anchor: .top)
  }

  private func bubble(_ message: ChatMessage) -> some View {
    ChatMessageBubble(model: model, original: message, vault: vault) { selected in
      if selected {
        selectedMessages.insert(message.id)
      } else {
        selectedMessages.remove(message.id)
      }
    }
  }

  private var welcome: some View {
    VStack(alignment: .leading, spacing: Self.welcomeSpacing) {
      Text("A little company.").font(
        .system(size: Self.welcomeTitleSize, weight: .bold, design: .rounded))
      Text("Pick an idea, or say hello.")
        .font(.callout).foregroundStyle(theme.secondary)
      if model.mode == .chat {
        ConversationStartersView(model: model, selected: focusComposer).padding(
          .top, Self.welcomeInset)
      }
    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, Self.welcomeInset)
  }
}
