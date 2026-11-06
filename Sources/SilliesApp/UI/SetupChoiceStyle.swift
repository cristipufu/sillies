import SwiftUI

/// Shared selection feedback for crew and activity choices.
struct SetupChoiceStyle: ButtonStyle {
  @Environment(\.silliesTheme) private var theme
  let isSelected: Bool
  private static let cornerRadius: CGFloat = 16
  private static let selectedBorder: CGFloat = 1.5
  private static let normalBorder: CGFloat = 0.8
  private static let pressedOpacity = 0.8

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .background(theme.card, in: RoundedRectangle(cornerRadius: Self.cornerRadius))
      .overlay(
        RoundedRectangle(cornerRadius: Self.cornerRadius).strokeBorder(
          isSelected ? theme.accent : theme.border,
          lineWidth: isSelected ? Self.selectedBorder : Self.normalBorder)
      )
      .opacity(configuration.isPressed ? Self.pressedOpacity : 1)
      .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
