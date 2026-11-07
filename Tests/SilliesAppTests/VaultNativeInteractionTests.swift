import AppKit
import SilliesCore
import Testing

@testable import SilliesApp

/// Opt-in WindowServer checks. All records and edits belong to a disposable Vault.
@Test @MainActor func vaultNativeSearchFocusAndReopeningPreserveTheDocument() async throws {
  let fixture = try await VaultNativeFixture.make()
  defer { fixture.close() }
  let window = try #require(fixture.owner.window)
  let root = try #require(window.contentView)
  let editor = try #require(
    fixture.textViews(in: root).first { !$0.isFieldEditor && $0.isEditable })
  #expect(window.makeFirstResponder(editor))
  editor.setSelectedRange(NSRange(location: 0, length: 0))
  editor.insertText("Saved edit. ", replacementRange: NSRange(location: NSNotFound, length: 0))
  let expected = editor.string
  #expect(expected.hasPrefix("Saved edit. "))
  let search = try fixture.command("f", keyCode: 3)
  #expect(window.performKeyEquivalent(with: search))
  try DisplayFrameSequence.presentCreatedWindows()
  let focused = try #require(window.firstResponder as? NSTextView)
  #expect(focused.isFieldEditor)
  #expect(focused !== editor)
  focused.insertText(
    "navigation",
    replacementRange: NSRange(location: 0, length: (focused.string as NSString).length))
  #expect(fixture.owner.model.workspace.searchText == "navigation")
  #expect(fixture.owner.model.workspace.document.editor.text == expected)
  fixture.owner.hide()
  fixture.owner.show(.record(fixture.id))
  try await fixture.waitForDocument()
  try DisplayFrameSequence.presentCreatedWindows()
  #expect(fixture.owner.window === window)
  #expect(window.isKeyWindow)
  #expect(fixture.owner.model.workspace.document.editor.text == expected)
  #expect(window.attachedSheet == nil)
  await fixture.vault.flush()
}

@Test @MainActor func vaultNativeResizeAndScrollKeepAReadableViewport() async throws {
  let fixture = try await VaultNativeFixture.make()
  defer { fixture.close() }
  let window = try #require(fixture.owner.window)
  let root = try #require(window.contentView)
  let editor = try #require(
    fixture.textViews(in: root).first { !$0.isFieldEditor && $0.isEditable })
  let scroll = try #require(editor.enclosingScrollView)
  var samples: [Double] = []
  var intervals: [Double] = []
  var previous = ContinuousClock.now
  try DisplayFrameSequence.run(count: 48) { frame in
    let started = ContinuousClock.now
    intervals.append(VaultNativeFixture.milliseconds(previous.duration(to: started)))
    previous = started
    let fraction = Double(frame % 24) / 23
    let minimum = SessionVaultWindowController.minimumSize
    let maximum = SessionVaultWindowController.initialSize
    window.setContentSize(
      CGSize(
        width: minimum.width + (maximum.width - minimum.width) * fraction,
        height: minimum.height + (maximum.height - minimum.height) * fraction))
    root.layoutSubtreeIfNeeded()
    let available = max(0, editor.bounds.height - scroll.contentView.bounds.height)
    scroll.contentView.scroll(to: CGPoint(x: 0, y: available * fraction))
    scroll.reflectScrolledClipView(scroll.contentView)
    samples.append(VaultNativeFixture.milliseconds(started.duration(to: .now)))
    #expect(scroll.contentView.bounds.height > 100)
    #expect(scroll.contentView.bounds.width > 180)
  }
  #expect(samples.count == 48)
  try fixture.recordTiming(samples: samples, intervals: Array(intervals.dropFirst()))
}
