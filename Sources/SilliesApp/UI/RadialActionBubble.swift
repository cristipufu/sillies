import SilliesCore
import SwiftUI

/// Both menus share their artwork, typography, selection and orbital guide.
struct RadialActionBubble: View {
  @Environment(\.silliesTheme) private var theme
  let title: String
  let symbol: String
  let isSelected: Bool
  var titleWidth: CGFloat?
  var body: some View {
    VStack(spacing: RadialMenuItemLayout.spacing) {
      ZStack {
        Circle()
          .fill(isSelected ? theme.accentFill : theme.card.opacity(0.98))
          .frame(
            width: RadialMenuItemLayout.iconDiameter, height: RadialMenuItemLayout.iconDiameter
          )
          .shadow(
            color: isSelected
              ? theme.accent.opacity(0.42)
              : Color.black.opacity(0.16),
            radius: 6, y: 2
          )
          .overlay(
            Circle().strokeBorder(
              isSelected ? theme.onAccent.opacity(0.9) : theme.border,
              lineWidth: isSelected ? 2 : 1))
        Image(systemName: symbol)
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(isSelected ? theme.onAccent : theme.ink)
      }
      Text(title)
        .lineLimit(1)
        .font(.system(size: 10.5, weight: .bold, design: .rounded))
        .padding(.horizontal, 8)
        .padding(.vertical, 2.5)
        .frame(width: titleWidth, height: RadialMenuItemLayout.titleHeight)
        .background(
          Capsule().fill(
            isSelected ? theme.accentFill : theme.card.opacity(0.97))
        )
        .overlay(
          Capsule().strokeBorder(
            isSelected ? theme.onAccent.opacity(0.5) : theme.border.opacity(0.8),
            lineWidth: 0.7)
        )
        .foregroundStyle(isSelected ? theme.onAccent : theme.ink)
        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
    }
    .scaleEffect(isSelected ? RadialMenuItemLayout.selectedScale : 1)
  }
}

struct RadialMenuOrbit: View {
  @Environment(\.silliesTheme) private var theme
  let radius: CGFloat
  var body: some View {
    ZStack {
      Circle().strokeBorder(
        theme.accent.opacity(0.28),
        style: StrokeStyle(lineWidth: 1.2, dash: [4, 5])
      )
      .frame(width: radius * 2, height: radius * 2)
      Circle().fill(theme.accent.opacity(0.08)).frame(width: 54, height: 54)
        .overlay(Circle().strokeBorder(theme.accent.opacity(0.35), lineWidth: 1.2))
    }
    .allowsHitTesting(false)
  }
}
