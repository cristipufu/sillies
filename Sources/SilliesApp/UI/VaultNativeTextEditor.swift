import AppKit
import SilliesCore
import SwiftUI

/// TextKit owns selection, IME, undo and viewport layout for the currently loaded section range.
struct VaultNativeTextEditor: NSViewRepresentable {
  static let scrollIdentifier = NSUserInterfaceItemIdentifier("vault.document.text")
  @Environment(\.silliesTheme) private var theme
  let model: VaultTextEditorModel
  var isPresented: Bool
  var allowsEditing = true
  var openSource: ((VaultSourceReference) -> Void)?
  private static let fontSize: CGFloat = 14
  private static let textInset = NSSize(width: 22, height: 20)
  private static let paragraphSpacing: CGFloat = 5
  private static let screenshotFontSize: CGFloat = 13
  private static let screenshotLineSpacing: CGFloat = 3

  func makeCoordinator() -> Coordinator { Coordinator(model: model) }
  func makeNSView(context: Context) -> NSScrollView {
    let scroll = NSScrollView()
    scroll.identifier = Self.scrollIdentifier
    scroll.hasVerticalScroller = true
    scroll.drawsBackground = false
    let text = NSTextView(usingTextLayoutManager: true)
    text.isRichText = false
    text.allowsUndo = true
    text.isVerticallyResizable = true
    text.isHorizontallyResizable = false
    text.autoresizingMask = [.width]
    text.textContainer?.widthTracksTextView = true
    text.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
    text.textContainerInset = Self.textInset
    text.font = .systemFont(ofSize: Self.fontSize)
    text.drawsBackground = false
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = Self.paragraphSpacing
    text.defaultParagraphStyle = paragraph
    text.delegate = context.coordinator
    scroll.documentView = text
    context.coordinator.scroll = scroll
    context.coordinator.observeScrolling(scroll)
    return scroll
  }

  func updateNSView(_ scroll: NSScrollView, context: Context) {
    guard let text = scroll.documentView as? NSTextView else { return }
    context.coordinator.model = model
    context.coordinator.openSource = openSource
    context.coordinator.observeUndo(in: text)
    text.isEditable = model.canAcceptEdits && isPresented && allowsEditing
    text.isSelectable = isPresented
    text.textColor = NSColor(theme.ink)
    text.insertionPointColor = NSColor(theme.accent)
    let isScreenshotText = model.location?.section == .screenshotText
    let font: NSFont =
      isScreenshotText
      ? .monospacedSystemFont(ofSize: Self.screenshotFontSize, weight: .regular)
      : .systemFont(ofSize: Self.fontSize)
    if text.font != font {
      text.font = font
      let paragraph = NSMutableParagraphStyle()
      paragraph.lineSpacing = isScreenshotText ? Self.screenshotLineSpacing : Self.paragraphSpacing
      text.defaultParagraphStyle = paragraph
    }
    text.setAccessibilityLabel(model.location?.section.title ?? String(localized: "My notes"))
    if context.coordinator.identity != model.identity {
      context.coordinator.isRestoring = true
      defer { context.coordinator.isRestoring = false }
      context.coordinator.rememberPosition()
      context.coordinator.identity = model.identity
      context.coordinator.location = model.location
      text.string = model.text
      context.coordinator.applySourceLinks(in: text)
      text.undoManager?.removeAllActions()
      if let location = model.location, let position = model.readingState.position(at: location) {
        let length = (text.string as NSString).length
        text.setSelectedRange(VaultTextRange.clamped(position.selection, toLength: length))
        scroll.contentView.scroll(to: position.origin)
        scroll.reflectScrolledClipView(scroll.contentView)
      } else {
        text.setSelectedRange(NSRange(location: 0, length: 0))
        text.scrollToBeginningOfDocument(nil)
      }
    }
    context.coordinator.applyFormatting(in: text)
    context.coordinator.revealRequestedText(in: text)
    if !isPresented, text.window?.firstResponder === text { text.window?.makeFirstResponder(nil) }
  }

  static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
    coordinator.rememberPosition()
    coordinator.stopObserving()
    (scroll.documentView as? NSTextView)?.delegate = nil
  }

  @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
    var model: VaultTextEditorModel
    var identity: UUID?
    var location: VaultBlockLocation?
    weak var scroll: NSScrollView?
    var openSource: ((VaultSourceReference) -> Void)?
    var isRestoring = false
    private var scrollObserver: NSObjectProtocol?
    private weak var observedUndoManager: UndoManager?
    private var undoObservers: [NSObjectProtocol] = []
    private var formattedRequest: UUID?
    private var revealedRequest: UUID?
    func revealRequestedText(in text: NSTextView) {
      guard let request = model.revealRequest, request.id != revealedRequest else { return }
      revealedRequest = request.id
      guard VaultTextRange.contains(request.range, inLength: (text.string as NSString).length)
      else { return }
      text.scrollRangeToVisible(request.range)
      if request.presentation == .passage { text.showFindIndicator(for: request.range) }
    }
    init(model: VaultTextEditorModel) {
      self.model = model
      formattedRequest = model.formattingRequest?.id
    }
    func textDidChange(_ notification: Notification) {
      guard let text = notification.object as? NSTextView else { return }
      observeUndo(in: text)
      synchronizeText(text)
    }

    private func synchronizeText(_ text: NSTextView) {
      guard !isRestoring, !text.hasMarkedText() else { return }
      model.replaceText(text.string)
      applySourceLinks(in: text)
    }

    /// TextKit's undo operations can update storage without sending textDidChange to its delegate.
    func observeUndo(in text: NSTextView) {
      guard observedUndoManager !== text.undoManager else { return }
      stopObservingUndo()
      guard let manager = text.undoManager else { return }
      observedUndoManager = manager
      undoObservers = [
        Notification.Name.NSUndoManagerDidUndoChange, Notification.Name.NSUndoManagerDidRedoChange,
      ].map { name in
        NotificationCenter.default.addObserver(forName: name, object: manager, queue: .main) {
          [weak self, weak text] _ in
          MainActor.assumeIsolated {
            guard let text else { return }
            self?.synchronizeText(text)
          }
        }
      }
    }

    private func stopObservingUndo() {
      for observer in undoObservers { NotificationCenter.default.removeObserver(observer) }
      undoObservers = []
      observedUndoManager = nil
    }

    func textViewDidChangeSelection(_ notification: Notification) {
      guard !isRestoring, let text = notification.object as? NSTextView else { return }
      model.selectText(text.selectedRange())
    }

    func observeScrolling(_ scroll: NSScrollView) {
      stopObserving()
      scrollObserver = NotificationCenter.default.addObserver(
        forName: NSScrollView.willStartLiveScrollNotification, object: scroll, queue: .main
      ) { [weak self] _ in MainActor.assumeIsolated { self?.model.onInteraction?() } }
    }
    func stopObserving() {
      if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
      scrollObserver = nil
      stopObservingUndo()
    }
    func applySourceLinks(in text: NSTextView) {
      guard let storage = text.textStorage else { return }
      let whole = NSRange(location: 0, length: storage.length)
      storage.removeAttribute(.link, range: whole)
      let source = text.string
      var remaining = source.startIndex..<source.endIndex
      let maximumLinksPerPage = 128
      for _ in 0..<maximumLinksPerPage {
        guard
          let range = source.range(
            of: "sillies-vault://source/[A-Za-z0-9/?=&-]+",
            options: .regularExpression, range: remaining)
        else { break }
        let link = String(source[range])
        if VaultSourceReference(link: link) != nil {
          storage.addAttribute(.link, value: link, range: NSRange(range, in: source))
        }
        remaining = range.upperBound..<source.endIndex
      }
    }
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
      let value = (link as? URL)?.absoluteString ?? (link as? String)
      guard let value, let reference = VaultSourceReference(link: value) else { return false }
      openSource?(reference)
      return true
    }
    isolated deinit { stopObserving() }

    func rememberPosition() {
      guard let scroll, let text = scroll.documentView as? NSTextView, let location else { return }
      model.readingState.save(
        .init(selection: text.selectedRange(), origin: scroll.contentView.bounds.origin),
        at: location)
    }

    func applyFormatting(in text: NSTextView) {
      guard let request = model.formattingRequest, request.id != formattedRequest,
        text.isEditable, !text.hasMarkedText()
      else { return }
      formattedRequest = request.id
      let range = text.selectedRange()
      guard VaultTextRange.contains(range, inLength: (text.string as NSString).length) else {
        return
      }
      let selection = (text.string as NSString).substring(with: range)
      text.insertText(request.action.apply(to: selection), replacementRange: range)
      text.window?.makeFirstResponder(text)
    }

    func textView(
      _ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
      replacementString: String?
    ) -> Bool {
      guard let replacementString else { return true }
      let current = textView.string as NSString
      guard VaultTextRange.contains(affectedCharRange, inLength: current.length)
      else { return false }
      let replaced = current.substring(with: affectedCharRange).unicodeScalars.count
      let count =
        textView.string.unicodeScalars.count - replaced + replacementString.unicodeScalars.count
      guard count <= VaultTextBlocks.maximumEditableScalars else {
        model.reportEditLimit()
        return false
      }
      return true
    }
  }
}
