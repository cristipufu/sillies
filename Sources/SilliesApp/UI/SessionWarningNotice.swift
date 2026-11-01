import SwiftUI

/// Consistent readable, selectable warnings with actions supplied by the owning feature.
struct SessionWarningNotice<Actions: View>: View {
  @Environment(\.silliesTheme) private var theme
  let message: String
  @ViewBuilder let actions: () -> Actions

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(theme.warning)
      VStack(alignment: .leading, spacing: 8) {
        Text(message).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        actions()
      }
      Spacer(minLength: 0)
    }.font(.callout).padding(12)
      .background(theme.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
  }
}
