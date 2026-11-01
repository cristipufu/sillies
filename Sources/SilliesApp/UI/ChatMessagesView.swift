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
  @State private var selectionReset: UUID?
  private static let bottomID = "latest-chat-message"
  private static let bottomThreshold: CGFloat = 48

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 14) {
          if model.messages.isEmpty { welcome }
          ForEach(model.messages) { message in
            bubble(message).id(message.id)
              .transition(
                .asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity))
          }
          if model.isWorking {
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
        if current.contentHeight != previous.contentHeight, followsLatest, selectedMessages.isEmpty
        {
          proxy.scrollTo(Self.bottomID, anchor: .bottom)
        }
      }
      .onScrollPhaseChange { _, phase in
        if phase == .interacting { followsLatest = false }
        if phase == .idle, nearBottom { followsLatest = true }
      }
      .overlay(alignment: .bottom) {
        if !followsLatest || !selectedMessages.isEmpty, !nearBottom {
          Button("Latest", systemImage: "arrow.down") {
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
      Text("Say hello to \(model.companionName).\nType a thought, or start a voice conversation.")
        .font(.callout).foregroundStyle(theme.secondary).multilineTextAlignment(.center)
    }.frame(maxWidth: .infinity).padding(.vertical, 38)
  }
}
