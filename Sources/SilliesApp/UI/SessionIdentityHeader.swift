import SwiftUI

struct SessionIdentityHeader<Subtitle: View, Accessory: View>: View {
  @Environment(\.silliesTheme) private var theme
  let title: String
  let symbol: String
  @ViewBuilder let subtitle: () -> Subtitle
  @ViewBuilder let accessory: () -> Accessory

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: symbol)
        .font(.system(size: 22, weight: .medium)).foregroundStyle(theme.accent)
        .frame(width: 48, height: 48)
        .background(theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
      VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.system(size: 24, weight: .bold, design: .rounded))
        subtitle().font(.callout).foregroundStyle(theme.secondary)
      }
      Spacer(minLength: 12)
      accessory()
    }
  }
}
