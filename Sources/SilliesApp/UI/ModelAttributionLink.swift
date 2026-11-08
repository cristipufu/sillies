import SilliesCore
import SwiftUI

struct ModelAttributionLink: View {
  @Environment(\.silliesTheme) private var theme
  let attribution: ModelAttribution

  var body: some View {
    // Credit is publisher-supplied legal text, retained verbatim rather than translated UI copy.
    Link(destination: attribution.url) { Text(verbatim: attribution.text) }
      .font(.caption2).foregroundStyle(theme.accent)
  }
}
