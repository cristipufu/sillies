import SwiftUI

/// Explicit foreground/background pairs keep custom palettes readable in inactive windows too.
struct AccentButtonStyle: ButtonStyle {
  @Environment(\.silliesTheme) private var theme
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.controlSize) private var controlSize
  @Environment(\.isFocused) private var isFocused

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .padding(.horizontal, horizontalPadding).padding(.vertical, verticalPadding)
      .foregroundStyle(isEnabled ? theme.onAccent : theme.secondary)
      .background(
        isEnabled ? theme.accentFill : theme.soft,
        in: RoundedRectangle(cornerRadius: 9)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 9).strokeBorder(
          isFocused ? theme.onAccent : .clear, lineWidth: 2)
      )
      .opacity(configuration.isPressed ? 0.88 : 1)
  }

  private var horizontalPadding: CGFloat {
    switch controlSize {
    case .mini, .small: 8
    case .large, .extraLarge: 16
    default: 12
    }
  }
  private var verticalPadding: CGFloat {
    switch controlSize {
    case .mini, .small: 4
    case .large, .extraLarge: 9
    default: 6
    }
  }
}
