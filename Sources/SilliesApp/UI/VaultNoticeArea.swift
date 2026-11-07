import SwiftUI

/// Long, selectable diagnostics stay available without displacing the document viewport.
struct VaultNoticeArea<Content: View>: View {
  private static var maximumHeight: CGFloat { 120 }
  @ViewBuilder let content: () -> Content

  var body: some View {
    NoticeViewport(maximumHeight: Self.maximumHeight, content: content)
  }
}
