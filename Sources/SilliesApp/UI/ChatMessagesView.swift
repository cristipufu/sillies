import AppKit
import SilliesChat
import SilliesCore
import SwiftUI

struct ChatMessagesView: View {
  @Environment(\.silliesTheme) private var theme
  let model: ChatSession
  let motion: ChatPresentationMotion
  var vault: ChatVaultPresentation? = nil
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  private var reduceMotion: Bool { systemReduceMotion || motion == .reduced }
  @State private var followsLatest = true
  @State private var nearBottom = true
  @State private var selectedMessages: Set<UUID> = []
  @State private var visibleMessages: Set<UUID> = []
  @State private var selectionReset: UUID?
  private static let bottomID = "latest-chat-message"
  private static let bottomThreshold: CGFloat = 48
  private var navigation: ConversationNavigation {
    .init(
      latestMessageID: model.messages.last?.id, hasEarlierMessages: model.hasEarlierMessages,
      page: model.browser.page, nearBottom: nearBottom)
  }

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 14) {
          if model.messages.isEmpty { welcome }
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
              .font(.callout).foregroundStyle(theme.secondary).padding(12)
          }
          Color.clear.frame(height: 1).id(Self.bottomID)
        }.padding(18)
          .environment(\.chatSelectionReset, selectionReset)
          .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.messages.count)
      }
      .defaultScrollAnchor(.bottom, for: .initialOffset)
      .defaultScrollAnchor(.bottom, for: .alignment)
      .onScrollGeometryChange(for: Viewport.self) { geometry in
        Viewport(
          contentHeight: geometry.contentSize.height,
          nearBottom: geometry.contentSize.height - geometry.visibleRect.maxY
            <= Self.bottomThreshold)
      } action: { previous, current in
        nearBottom = current.nearBottom
        if current.contentHeight != previous.contentHeight, followsLatest, selectedMessages.isEmpty,
          model.browser.page == nil
        {
          proxy.scrollTo(Self.bottomID, anchor: .bottom)
        }
      }
      .onAppear {
        if let id = model.browser.focusedMessageID ?? model.history.checkpoint.readingMessageID {
          followsLatest = false
          if model.messages.contains(where: { $0.id == id }) || model.browser.page != nil {
            proxy.scrollTo(id, anchor: .top)
          } else {
            Task { await model.browser.show(.around(id)) }
          }
        }
      }
      .onChange(of: model.browser.focusedMessageID) { _, id in
        guard let id else { return }
        followsLatest = false
        proxy.scrollTo(id, anchor: .top)
        model.browser.rememberPosition(id)
      }
      .onScrollPhaseChange { _, phase in
        if phase == .interacting { followsLatest = false }
        if phase == .idle, nearBottom, model.browser.page == nil {
          followsLatest = true
          model.browser.rememberPosition(nil)
        }
      }
      .overlay(alignment: .bottom) {
        if navigation.showsLatest {
          Button("Latest", systemImage: "arrow.down") {
            model.browser.showLatest()
            followsLatest = true
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
    VStack(spacing: 12) {
      Image(systemName: "bubble.left.and.bubble.right.fill")
        .font(.system(size: 38)).foregroundStyle(theme.accent)
      Text("A little company.").font(.system(size: 24, weight: .bold, design: .rounded))
      Text("Say hello to \(model.companionName).\nPick up wherever you left off.")
        .font(.callout).foregroundStyle(theme.secondary).multilineTextAlignment(.center)
    }.frame(maxWidth: .infinity).padding(.vertical, 38)
  }
}
