import SwiftUI

struct SessionIdentityHeader<Subtitle: View, Accessory: View>: View {
  let title: String
  let symbol: String
  @ViewBuilder let subtitle: () -> Subtitle
  @ViewBuilder let accessory: () -> Accessory

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: symbol)
        .font(.system(size: 22, weight: .medium)).foregroundStyle(SilliesTheme.accent)
        .frame(width: 48, height: 48)
        .background(SilliesTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
      VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.system(size: 24, weight: .bold, design: .rounded))
        subtitle().font(.callout).foregroundStyle(SilliesTheme.secondary)
      }
      Spacer(minLength: 12)
      accessory()
    }
  }
}
