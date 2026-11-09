import AppKit
import SwiftUI
import Testing

@testable import SilliesApp

@Test @MainActor func chatMarkdownRendersInlineFormattingAndNativeLinks() throws {
  let text = ChatMarkdownText(
    "**Bold** and *italic*, ***both***, `a **literal**`, ~~gone~~, [site](https://example.com)"
  )
  .render(style: markdownStyle())
  #expect(text.string == "Bold and italic, both, a **literal**, gone, site")
  #expect(try markdownFont("Bold", in: text).fontDescriptor.symbolicTraits.contains(.bold))
  #expect(try markdownFont("italic", in: text).fontDescriptor.symbolicTraits.contains(.italic))
  let both = try markdownFont("both", in: text).fontDescriptor.symbolicTraits
  #expect(both.contains(.bold) && both.contains(.italic))
  #expect(try markdownFont("a **literal**", in: text).isFixedPitch)
  #expect(
    text.attribute(
      .strikethroughStyle, at: (text.string as NSString).range(of: "gone").location,
      effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue)
  #expect(
    text.attribute(
      .link, at: (text.string as NSString).range(of: "site").location, effectiveRange: nil) as? URL
      == URL(string: "https://example.com"))
}

@Test @MainActor func chatMarkdownKeepsBlockStructureAndCodeLiteral() throws {
  let text = ChatMarkdownText(
    """
    # Heading

    First paragraph.
    Another line.

    - **One**
      - Nested
    - Two

    3. Three
    4. Four

    > A quotation.

    ```swift
    let text = "**literal**"
    print(text)
    ```
    """
  ).render(style: markdownStyle())
  #expect(
    text.string
      == "Heading\n\nFirst paragraph.\nAnother line.\n\n•\tOne\n•\tNested\n•\tTwo\n3.\tThree\n4.\tFour\n\nA quotation.\n\nlet text = \"**literal**\"\nprint(text)\n"
  )
  #expect(try markdownFont("Heading", in: text).pointSize > ChatReadingSize.standard.points)
  #expect(try markdownFont("let text", in: text).isFixedPitch)
  let nested = try #require(
    text.attribute(
      .paragraphStyle, at: (text.string as NSString).range(of: "Nested").location,
      effectiveRange: nil) as? NSParagraphStyle)
  let outer = try #require(
    text.attribute(
      .paragraphStyle, at: (text.string as NSString).range(of: "One").location, effectiveRange: nil)
      as? NSParagraphStyle)
  #expect(nested.headIndent > outer.headIndent)
}

@Test @MainActor func chatMarkdownStreamingKeepsSelectedWordsWhenDelimitersDisappear() throws {
  let view = ChatMessageTextView()
  let coordinator = ChatMessageText.Coordinator { _ in }
  coordinator.updateText(in: view, text: "Read **café 👋🏽", style: markdownStyle())
  view.setSelectedRange((view.string as NSString).range(of: "café 👋🏽"))
  for source in ["Read **café 👋🏽**", "Read **café 👋🏽** and another thought."] {
    coordinator.updateText(in: view, text: source, style: markdownStyle())
    #expect((view.string as NSString).substring(with: view.selectedRange()) == "café 👋🏽")
    #expect(
      try markdownFont("café", in: view.attributedString()).fontDescriptor.symbolicTraits.contains(
        .bold))
  }
}

@Test @MainActor func chatMarkdownAppearanceAndReadingSizeKeepFormattingAndSelection() throws {
  let view = ChatMessageTextView()
  let coordinator = ChatMessageText.Coordinator { _ in }
  let source = "**Bold** and `code`."
  coordinator.updateText(in: view, text: source, style: markdownStyle())
  view.setSelectedRange(NSRange(location: 0, length: 4))
  let style = ChatMarkdownText.Style(
    size: ChatReadingSize.large.points, ink: .white, codeBackground: .darkGray)
  coordinator.updateText(in: view, text: source, style: style)
  let bold = try markdownFont("Bold", in: view.attributedString())
  #expect(bold.pointSize == style.size && bold.fontDescriptor.symbolicTraits.contains(.bold))
  #expect(try markdownFont("code", in: view.attributedString()).isFixedPitch)
  #expect(view.selectedRange() == NSRange(location: 0, length: 4))
  #expect(
    view.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
      == style.ink)
  #expect(
    view.textStorage?.attribute(.backgroundColor, at: 9, effectiveRange: nil) as? NSColor
      == style.codeBackground)
}

@Test @MainActor func chatMarkdownPreservesPlainTextWhitespaceAndIncompleteInput() {
  for source in [
    "", "  ", "Read this 👋🏽 carefully. ", "First.\nSecond.\n\nThird.\n", "Unfinished **bold",
    "Unfinished `code",
  ] {
    #expect(ChatMarkdownText(source).render(style: markdownStyle()).string == source)
  }
}

@Test @MainActor func chatMarkdownKeepsEscapesAndTableCellsReadable() {
  let escaped = ChatMarkdownText(#"Keep \*literal\* and \*\*stars\*\*."#).render(
    style: markdownStyle())
  #expect(escaped.string == "Keep *literal* and **stars**.")
  let table = ChatMarkdownText("| Name | Value |\n| --- | --- |\n| Tea | **Warm** |").render(
    style: markdownStyle())
  #expect(table.string == "Name\tValue\nTea\tWarm")
}

@Test func chatTextReplacementBoundsInvalidSelectionsAndKeepsComposedCharacters() {
  let edit = ChatTextReplacement(previous: "👋", next: "👋🏽")
  #expect(edit.previousRange == NSRange(location: 0, length: 2))
  #expect(edit.nextRange == NSRange(location: 0, length: 4))
  #expect(edit.selection(NSRange(location: 0, length: 2)) == NSRange(location: 0, length: 4))
  #expect(
    edit.selection(NSRange(location: NSNotFound, length: 0)) == NSRange(location: 0, length: 0))
  #expect(edit.selection(NSRange(location: 1, length: Int.max)) == NSRange(location: 1, length: 3))
  #expect(
    edit.selection(NSRange(location: Int.max - 1, length: Int.max))
      == NSRange(location: 4, length: 0))
}

@Test @MainActor func chatMarkdownRestylesUnchangedCharactersWhenFormattingChanges() throws {
  let view = ChatMessageTextView()
  let coordinator = ChatMessageText.Coordinator { _ in }
  coordinator.updateText(in: view, text: "plain", style: markdownStyle())
  view.setSelectedRange(NSRange(location: 0, length: 5))
  coordinator.updateText(in: view, text: "**plain**", style: markdownStyle())
  #expect(view.string == "plain" && view.selectedRange().length == 5)
  #expect(
    try markdownFont("plain", in: view.attributedString()).fontDescriptor.symbolicTraits.contains(
      .bold))
  coordinator.updateText(in: view, text: "plain", style: markdownStyle())
  #expect(
    try !markdownFont("plain", in: view.attributedString()).fontDescriptor.symbolicTraits.contains(
      .bold))
}

@Test @MainActor func chatMarkdownNativeViewFitsNarrowWidthsAndBothThemes() throws {
  let source =
    "# A small plan\n\nTry **bold**, *emphasis*, and [a link](https://example.com).\n\n- First idea\n- Another idea\n\n> A quiet thought.\n\n```swift\nlet greeting = \"Hello\"\n```"
  for scheme in [ColorScheme.light, .dark] {
    for reading in [ChatReadingSize.standard, .large] {
      try renderSkillInterface(
        ChatMessageText(
          text: source, color: SilliesTheme().native(.ink), selectionChanged: { _ in }
        )
        .padding(16)
        .background(SilliesTheme().paper)
        .environment(\.colorScheme, scheme)
        .environment(\.chatReadingSize, reading),
        size: CGSize(width: 280, height: 500),
        name: "sillies-chat-markdown-\(scheme)-\(reading.rawValue)")
    }
  }
}

@MainActor private func markdownStyle() -> ChatMarkdownText.Style {
  .init(
    size: ChatReadingSize.standard.points, ink: .labelColor, codeBackground: .textBackgroundColor)
}

@MainActor private func markdownFont(_ substring: String, in text: NSAttributedString) throws
  -> NSFont
{
  let range = (text.string as NSString).range(of: substring)
  #expect(range.location != NSNotFound)
  return try #require(text.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
}
