import AppKit
import SwiftUI

/// AppKit must know the final viewport before positioning a status-item popover.
@MainActor
final class ControlCenterHostingController: NSHostingController<AnyView> {
  private static let width: CGFloat = 388
  private static let maximumHeight: CGFloat = 640
  private static let screenMargin: CGFloat = 24
  private let content: ControlCenterView
  private(set) var viewportSize: CGSize = .zero

  init(content: ControlCenterView, visibleFrame: CGRect) {
    self.content = content
    super.init(rootView: AnyView(EmptyView()))
    sizingOptions = []
    updateViewport(visibleFrame: visibleFrame)
  }

  @MainActor required dynamic init?(coder: NSCoder) { nil }

  func updateViewport(visibleFrame: CGRect) {
    let size = CGSize(
      width: Self.width,
      height: max(1, min(Self.maximumHeight, visibleFrame.height - Self.screenMargin)))
    guard viewportSize != size else { return }
    viewportSize = size
    rootView = AnyView(
      ControlCenterViewport(content: content, size: size))
    preferredContentSize = size
    view.setFrameSize(size)
    view.layoutSubtreeIfNeeded()
  }
}

private struct ControlCenterViewport: View {
  let content: ControlCenterView
  let size: CGSize
  var body: some View {
    ScrollView(.vertical) { content }
      .scrollBounceBehavior(.basedOnSize)
      .frame(width: size.width, height: size.height)
      .background(SilliesTheme.paper)
  }
}
