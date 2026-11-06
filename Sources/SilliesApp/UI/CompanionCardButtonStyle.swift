import SwiftUI

/// Paint-only feedback keeps the native portrait and the surrounding grid still.
struct CompanionCardButtonStyle: ButtonStyle {
  @Environment(\.silliesTheme) private var theme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorSchemeContrast) private var contrast
  let isSelected: Bool
  let isHovered: Bool
  let cornerRadius: CGFloat

  private static let feedbackDuration: Double = 0.16
  private static let selectedBorder: CGFloat = 1.5
  private static let normalBorder: CGFloat = 0.8
  private static let highContrastBorder: CGFloat = 2
  private static let pressedOpacity = 0.09
  private static let restingShadow = Shadow(opacity: 0.025, radius: 2, offset: 1)
  private static let hoveredShadow = Shadow(opacity: 0.09, radius: 7, offset: 3)

  private struct Shadow {
    let opacity: Double
    let radius: CGFloat
    let offset: CGFloat
  }

  func makeBody(configuration: Configuration) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    let shadow = isHovered ? Self.hoveredShadow : Self.restingShadow
    configuration.label
      .background(theme.card)
      .overlay(
        theme.accent.opacity(configuration.isPressed ? Self.pressedOpacity : 0)
          .allowsHitTesting(false)
      )
      .clipShape(shape)
      .overlay(
        shape.strokeBorder(
          isSelected || isHovered ? theme.accent : theme.border,
          lineWidth: borderWidth
        ).allowsHitTesting(false)
      )
      .shadow(
        color: theme.ink.opacity(shadow.opacity), radius: shadow.radius, x: 0, y: shadow.offset
      )
      .animation(
        reduceMotion ? nil : .easeOut(duration: Self.feedbackDuration), value: isHovered
      )
      .animation(
        reduceMotion ? nil : .easeOut(duration: Self.feedbackDuration),
        value: configuration.isPressed)
  }

  private var borderWidth: CGFloat {
    if contrast == .increased { return Self.highContrastBorder }
    return isSelected ? Self.selectedBorder : Self.normalBorder
  }
}
