import SwiftUI

struct SoftButtonStyle: ButtonStyle {
  @Environment(\.silliesTheme) private var theme
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .padding(.horizontal, 12).padding(.vertical, 8)
      .background(
        theme.accent.opacity(configuration.isPressed ? 0.20 : 0.10),
        in: RoundedRectangle(cornerRadius: 9)
      )
      .foregroundStyle(theme.accent)
  }
}
