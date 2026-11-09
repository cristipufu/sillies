import AppKit

/// Foundation parses Markdown; this adapter supplies native fonts and block layout without HTML.
@MainActor struct ChatMarkdownText {
  struct Style: Equatable {
    let size: CGFloat
    let ink: NSColor
    let codeBackground: NSColor
  }

  private static let listIndent: CGFloat = 20
  private static let quoteIndent: CGFloat = 16
  private static let headingScales: [CGFloat] = [1.45, 1.3, 1.2, 1.1, 1.05, 1]
  private let source: String
  private let parsed: AttributedString?

  init(_ source: String) {
    self.source = source
    do {
      parsed = try AttributedString(
        markdown: source,
        options: .init(interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible))
    } catch {
      // Malformed or unfinished input remains readable, including during streaming.
      parsed = nil
    }
  }

  func render(style: Style) -> NSAttributedString {
    let base = attributes(style: style, block: Block(nil), inline: [])
    guard let parsed, !parsed.characters.isEmpty else {
      return NSAttributedString(string: source, attributes: base)
    }
    let result = NSMutableAttributedString()
    var previous: Block?
    for run in parsed.runs {
      let block = Block(run.presentationIntent)
      let inline = run.inlinePresentationIntent ?? []
      var attributes = attributes(style: style, block: block, inline: inline)
      if let link = run.link { attributes[.link] = link }
      if block.identity != previous?.identity {
        appendSeparator(block.separator(after: previous), to: result, attributes: base)
        result.append(
          NSAttributedString(string: block.prefix(after: previous), attributes: attributes))
      }
      let text =
        inline.contains(.softBreak) || inline.contains(.lineBreak)
        ? "\n" : String(parsed[run.range].characters)
      result.append(NSAttributedString(string: text, attributes: attributes))
      previous = block
    }
    if previous?.isCode != true {
      let trailingWhitespace = source.reversed().prefix(while: { $0.isWhitespace }).reversed()
      result.append(NSAttributedString(string: String(trailingWhitespace), attributes: base))
    }
    return result
  }

  private func appendSeparator(
    _ separator: String, to result: NSMutableAttributedString,
    attributes: [NSAttributedString.Key: Any]
  ) {
    guard result.length > 0 else { return }
    let existingNewlines = result.string.reversed().prefix(while: { $0 == "\n" }).count
    let missing = separator == "\t" ? separator : String(separator.dropFirst(existingNewlines))
    result.append(NSAttributedString(string: missing, attributes: attributes))
  }

  private func attributes(style: Style, block: Block, inline: InlinePresentationIntent)
    -> [NSAttributedString.Key: Any]
  {
    let isCode = block.isCode || inline.contains(.code)
    let scale =
      block.heading.map { Self.headingScales[min(max($0, 1), Self.headingScales.count) - 1] } ?? 1
    var font =
      isCode
      ? NSFont.monospacedSystemFont(ofSize: style.size, weight: .regular)
      : NSFont.systemFont(ofSize: style.size * scale)
    if inline.contains(.stronglyEmphasized) || block.heading != nil || block.isTableHeader {
      font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
    }
    if inline.contains(.emphasized) {
      font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
    }
    let paragraph = NSMutableParagraphStyle()
    paragraph.setParagraphStyle(ChatTypography.paragraphStyle)
    paragraph.headIndent =
      CGFloat(block.listDepth) * Self.listIndent + CGFloat(block.quoteDepth) * Self.quoteIndent
    paragraph.firstLineHeadIndent = max(
      0, paragraph.headIndent - (block.listDepth > 0 ? Self.listIndent : 0))
    if block.listDepth > 0 {
      paragraph.tabStops = [NSTextTab(textAlignment: .left, location: paragraph.headIndent)]
      paragraph.defaultTabInterval = Self.listIndent
    }
    var attributes: [NSAttributedString.Key: Any] = [
      .font: font, .foregroundColor: style.ink, .paragraphStyle: paragraph,
    ]
    if isCode { attributes[.backgroundColor] = style.codeBackground }
    if inline.contains(.strikethrough) {
      attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
    }
    return attributes
  }

  private struct Block {
    let components: [PresentationIntent.IntentType]
    init(_ intent: PresentationIntent?) { components = intent?.components ?? [] }
    var identity: Int? { components.first?.identity }
    var heading: Int? {
      for component in components {
        if case .header(let level) = component.kind { return level }
      }
      return nil
    }
    var isCode: Bool {
      components.contains { if case .codeBlock = $0.kind { true } else { false } }
    }
    var isTableHeader: Bool { components.contains { $0.kind == .tableHeaderRow } }
    var listDepth: Int {
      components.count { $0.kind == .orderedList || $0.kind == .unorderedList }
    }
    var quoteDepth: Int { components.count { $0.kind == .blockQuote } }
    var item: PresentationIntent.IntentType? {
      components.first { if case .listItem = $0.kind { true } else { false } }
    }
    var tableRow: Int? {
      components.first {
        switch $0.kind {
        case .tableHeaderRow, .tableRow: true
        default: false
        }
      }?.identity
    }
    func prefix(after previous: Block?) -> String {
      guard let item, item.identity != previous?.item?.identity,
        case .listItem(let ordinal) = item.kind
      else { return "" }
      let list = components.first { $0.kind == .orderedList || $0.kind == .unorderedList }
      return list?.kind == .orderedList ? "\(ordinal).\t" : "•\t"
    }
    func separator(after previous: Block?) -> String {
      guard let previous else { return "" }
      if let tableRow, tableRow == previous.tableRow { return "\t" }
      if tableRow != nil, previous.tableRow != nil { return "\n" }
      if item != nil, previous.item != nil, item?.identity != previous.item?.identity {
        return "\n"
      }
      return "\n\n"
    }
  }
}
