import AppKit
import SilliesChat
import SilliesCore
import SwiftUI

struct ChatMessagesView: View {
  @Environment(\.silliesTheme) private var theme
  let model: ChatSession
  let motion: ChatPresentationMotion
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  private var reduceMotion: Bool { systemReduceMotion || motion == .reduced }
  @State private var followsLatest = true
  @State private var nearBottom = true
  @State private var selectedMessages: Set<UUID> = []
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
          .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.messages.count)
      }
      .defaultScrollAnchor(.bottom, for: .initialOffset)
      .defaultScrollAnchor(.bottom, for: .alignment)
      .onScrollGeometryChange(for: Bool.self) { geometry in
        geometry.contentSize.height - geometry.visibleRect.maxY <= Self.bottomThreshold
      } action: { _, value in
        nearBottom = value
      }
      .onScrollPhaseChange { _, phase in
        if phase == .interacting { followsLatest = false }
        if phase == .idle, nearBottom { followsLatest = true }
      }
      .onChange(of: model.messages.last?.id) {
        guard followsLatest, selectedMessages.isEmpty else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
          proxy.scrollTo(Self.bottomID, anchor: .bottom)
        }
      }
      .overlay(alignment: .bottom) {
        if !followsLatest, !nearBottom {
          Button("Latest", systemImage: "arrow.down") {
            followsLatest = true
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
              proxy.scrollTo(Self.bottomID, anchor: .bottom)
            }
          }.buttonStyle(AccentButtonStyle()).clipShape(Capsule()).padding(12)
        }
      }
    }
  }

  private func bubble(_ message: ChatMessage) -> some View {
    let fromUser = message.role == .user
    return HStack(alignment: .bottom, spacing: 0) {
      if fromUser { Spacer(minLength: 52) }
      VStack(alignment: .leading, spacing: 5) {
        Text(fromUser ? String(localized: "You") : model.companionName)
          .font(.system(size: 11, weight: .semibold, design: .rounded))
          .foregroundStyle(fromUser ? theme.onAccent.opacity(0.8) : theme.secondary)
        ChatMessageText(text: message.text, color: theme.native(fromUser ? .onAccent : .ink)) {
          selected in
          if selected {
            selectedMessages.insert(message.id)
          } else {
            selectedMessages.remove(message.id)
          }
        }
      }
      .padding(.horizontal, 14).padding(.vertical, 11)
      .background(
        fromUser ? theme.accentFill : theme.card,
        in: RoundedRectangle(cornerRadius: 18)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 18).strokeBorder(
          fromUser ? Color.clear : theme.border)
      )
      .contextMenu {
        Button("Copy message", systemImage: "doc.on.doc") {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(message.text, forType: .string)
        }
      }
      if !fromUser { Spacer(minLength: 52) }
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
