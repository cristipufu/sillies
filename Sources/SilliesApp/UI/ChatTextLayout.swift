import AppKit

/// SwiftUI may probe several widths before assigning a frame. Never measure using the live view's
/// width-tracking container: it can undo a proposal and leave native drawing with a stale layout.
@MainActor final class ChatTextLayout {
  private static let maximumCachedWidths = 4
  private let storage = NSTextStorage()
  private let layout = NSLayoutManager()
  private let container = NSTextContainer()
  private var sizes: [CGFloat: CGSize] = [:]

  init() {
    container.lineFragmentPadding = 0
    layout.addTextContainer(container)
    storage.addLayoutManager(layout)
  }

  func size(of text: NSAttributedString, width: CGFloat) -> CGSize? {
    guard width.isFinite, width > 0 else { return nil }
    if !storage.isEqual(to: text) {
      storage.setAttributedString(text)
      sizes.removeAll(keepingCapacity: true)
    }
    if let size = sizes[width] { return size }
    container.containerSize = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
    layout.ensureLayout(for: container)
    let used = layout.usedRect(for: container)
    let size = CGSize(
      width: min(width, ceil(used.width)),
      height: max(ChatTypography.minimumLineHeight, ceil(used.height)))
    if sizes.count == Self.maximumCachedWidths { sizes.removeAll(keepingCapacity: true) }
    sizes[width] = size
    return size
  }
}
