import SwiftUI

struct ThemedContent<Content: View>: View {
  let appearance: ThemeEnvironment
  let content: Content
  var body: some View { content.environment(\.silliesTheme, appearance.palette) }
}
