import SwiftUI

@MainActor
final class ThemedHostingController<Content: View>: NSHostingController<ThemedContent<Content>> {
  private let themeEnvironment: ThemeEnvironment
  var content: Content {
    get { rootView.content }
    set { rootView = ThemedContent(appearance: themeEnvironment, content: newValue) }
  }
  init(rootView: Content, appearance: ThemeEnvironment) {
    self.themeEnvironment = appearance
    super.init(rootView: ThemedContent(appearance: appearance, content: rootView))
  }
  @MainActor required dynamic init?(coder: NSCoder) { nil }
}
