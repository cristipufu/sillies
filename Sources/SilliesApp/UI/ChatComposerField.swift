import SilliesChat
import SwiftUI

/// One input surface owns the draft and its primary action; native editing retains IME and copy.
struct ChatComposerField: View {
  @Environment(\.silliesTheme) private var theme
  @Bindable var model: ChatSession
  var focusRequest: UUID? = nil
  @Environment(\.chatReadingSize) private var readingSize
  @State private var isFocused = false
  private static let cornerRadius: CGFloat = 14
  private static let actionSize: CGFloat = 36
  private static let inset: CGFloat = 8
  private static let actionSpacing: CGFloat = 6

  var body: some View {
    HStack(alignment: .bottom, spacing: Self.actionSpacing) {
      ZStack(alignment: .topLeading) {
        ChatComposer(
          text: $model.draft,
          isEditable: model.history.isLoaded && model.phase != .finished,
          send: model.send, focusChanged: { isFocused = $0 }, focusRequest: focusRequest)
        if model.draft.isEmpty {
          Text("Message \(model.companionName)…")
            .font(.system(size: readingSize.points))
            .foregroundStyle(theme.secondary)
            .padding(.horizontal, ChatComposer.textInset.width)
            .padding(.vertical, ChatComposer.textInset.height)
            .allowsHitTesting(false)
        }
      }
      action.padding(.bottom, Self.actionSpacing)
    }
    .padding(Self.inset)
    .background(theme.card, in: RoundedRectangle(cornerRadius: Self.cornerRadius))
    .overlay(
      RoundedRectangle(cornerRadius: Self.cornerRadius)
        .strokeBorder(isFocused ? theme.accent.opacity(0.65) : theme.border)
    )
    .help("Return to send · Shift–Return for a new line")
  }

  private var action: some View {
    Button {
      if model.isWorking { model.interrupt() } else { model.send() }
    } label: {
      Image(systemName: model.isWorking ? "stop.fill" : "arrow.up")
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(model.isWorking || model.canSend ? theme.onAccent : theme.secondary)
        .frame(width: Self.actionSize, height: Self.actionSize)
        .background(
          model.isWorking || model.canSend ? theme.accentFill : theme.border.opacity(0.55),
          in: Circle()
        )
        .contentShape(Circle())
    }
    .buttonStyle(.plain).disabled(!model.isWorking && !model.canSend)
    .accessibilityLabel(
      model.isWorking ? String(localized: "Stop reply") : String(localized: "Send message")
    )
    .help(model.isWorking ? String(localized: "Stop reply") : String(localized: "Send · Return"))
  }
}
