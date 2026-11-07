import SwiftUI

/// Measures only notice content. Short notices wrap; long ones retain a bounded scroll viewport.
struct NoticeViewport<Content: View>: View {
  let maximumHeight: CGFloat
  @ViewBuilder let content: () -> Content
  private static var initialHeight: CGFloat { 44 }
  @State private var contentHeight = Self.initialHeight

  var body: some View {
    ScrollView {
      content()
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) {
          $0.size.height
        } action: {
          contentHeight = $0
        }
    }
    .scrollBounceBehavior(.basedOnSize)
    .frame(height: min(maximumHeight, contentHeight))
  }
}
