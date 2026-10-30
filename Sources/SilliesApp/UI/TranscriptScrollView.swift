import AppKit
import SilliesCore

@MainActor
final class TranscriptScrollView: NSScrollView {
  enum FollowMode { case live, reading }
  private static let fontSize: CGFloat = 14
  private static let lineSpacing: CGFloat = 6
  private static let bottomTolerance: CGFloat = 2
  private let transcriptView = NSTextView()
  private lazy var textAttributes = makeTextAttributes()
  private var displayedText = ""
  private var latestText = ""
  private var followMode = FollowMode.reading
  private var isUpdatingText = false
  var onFollowModeChange: ((FollowMode) -> Void)?
  var textView: NSTextView { transcriptView }

  init() {
    super.init(frame: .zero)
    configureScrolling()
    configureText()
    NotificationCenter.default.addObserver(
      self, selector: #selector(didScroll), name: NSScrollView.didLiveScrollNotification,
      object: self)
    NotificationCenter.default.addObserver(
      self, selector: #selector(didSelectText), name: NSTextView.didChangeSelectionNotification,
      object: transcriptView)
    contentView.postsFrameChangedNotifications = true
    NotificationCenter.default.addObserver(
      self, selector: #selector(viewportDidResize), name: NSView.frameDidChangeNotification,
      object: contentView)
  }

  required init?(coder: NSCoder) { nil }

  private func configureScrolling() {
    drawsBackground = false
    hasVerticalScroller = true
    autohidesScrollers = true
    borderType = .noBorder
    documentView = transcriptView
  }

  private func configureText() {
    transcriptView.isEditable = false
    transcriptView.isRichText = false
    transcriptView.isSelectable = true
    transcriptView.drawsBackground = false
    transcriptView.isVerticallyResizable = true
    transcriptView.isHorizontallyResizable = false
    transcriptView.minSize = .zero
    transcriptView.maxSize = CGSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    transcriptView.autoresizingMask = [.width]
    transcriptView.textContainerInset = .zero
    transcriptView.textContainer?.lineFragmentPadding = 0
    transcriptView.textContainer?.widthTracksTextView = true
    transcriptView.textContainer?.containerSize = CGSize(
      width: 0, height: CGFloat.greatestFiniteMagnitude)
  }

  func update(text: String, followMode: FollowMode) {
    latestText = text
    let changed = displayedText != text
    let resumedFollowing = followMode == .live && self.followMode == .reading
    self.followMode = followMode
    guard followMode == .live || displayedText.isEmpty else { return }
    guard changed || resumedFollowing else { return }
    updateViewport {
      let origin = contentView.bounds.origin
      if changed { replaceText(text) }
      if resumedFollowing {
        transcriptView.setSelectedRange(
          NSRange(location: transcriptView.string.utf16.count, length: 0))
      }
      if followMode == .live {
        transcriptView.scrollToEndOfDocument(nil)
      } else {
        contentView.scroll(to: origin)
        reflectScrolledClipView(contentView)
      }
    }
  }

  private func updateViewport(_ update: () -> Void) {
    guard !isUpdatingText else { return }
    isUpdatingText = true
    defer { isUpdatingText = false }
    update()
  }

  private func replaceText(_ text: String) {
    let selection = transcriptView.selectedRange()
    if displayedText.isEmpty {
      transcriptView.textStorage?.setAttributedString(
        NSAttributedString(string: text, attributes: textAttributes))
    } else {
      apply(TranscriptTextChanges(replacing: displayedText, with: text))
    }
    let length = transcriptView.textStorage?.length ?? 0
    let start = min(selection.location, length)
    transcriptView.setSelectedRange(
      NSRange(location: start, length: min(selection.length, length - start)))
    displayedText = text
  }

  private func makeTextAttributes() -> [NSAttributedString.Key: Any] {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = Self.lineSpacing
    return [
      .font: NSFont.systemFont(ofSize: Self.fontSize), .foregroundColor: NSColor(SilliesTheme.ink),
      .paragraphStyle: paragraph,
    ]
  }

  private func apply(_ changes: TranscriptTextChanges) {
    guard let storage = transcriptView.textStorage else { return }
    // Separate edits retain layout between changed paragraphs instead of invalidating their union.
    for edit in changes.edits {
      let range = NSRange(location: edit.utf16Range.lowerBound, length: edit.utf16Range.count)
      storage.replaceCharacters(
        in: range, with: NSAttributedString(string: edit.replacement, attributes: textAttributes))
    }
  }

  override func scrollWheel(with event: NSEvent) {
    super.scrollWheel(with: event)
    didScroll()
  }

  @objc private func didScroll() {
    guard !isUpdatingText, transcriptView.selectedRange().length == 0 else { return }
    let atBottom = transcriptView.bounds.height - contentView.bounds.maxY <= Self.bottomTolerance
    requestFollowMode(atBottom ? .live : .reading)
  }

  @objc private func didSelectText() {
    guard !isUpdatingText, transcriptView.selectedRange().length > 0 else { return }
    requestFollowMode(.reading)
  }

  @objc private func viewportDidResize() {
    guard followMode == .live else { return }
    updateViewport { transcriptView.scrollToEndOfDocument(nil) }
  }

  private func requestFollowMode(_ mode: FollowMode) {
    guard followMode != mode else { return }
    if mode == .live { update(text: latestText, followMode: .live) } else { followMode = .reading }
    onFollowModeChange?(mode)
  }

  func stopObserving() {
    NotificationCenter.default.removeObserver(self)
    onFollowModeChange = nil
  }
}
