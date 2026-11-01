import SwiftUI

@MainActor final class ThemedHostingView<Content: View>: NSHostingView<ThemedContent<Content>> {
  convenience init(rootView: Content, appearance: ThemeEnvironment) {
    self.init(rootView: ThemedContent(appearance: appearance, content: rootView))
  }
  required init(rootView: ThemedContent<Content>) { super.init(rootView: rootView) }
  @MainActor required dynamic init?(coder: NSCoder) { nil }
}
