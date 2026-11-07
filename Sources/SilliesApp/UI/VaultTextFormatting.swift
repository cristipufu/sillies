import Foundation

enum VaultTextFormatting: String, CaseIterable, Identifiable {
  case heading, bold, emphasis, list, checklist, link, quote, code
  var id: Self { self }
  var symbol: String {
    switch self {
    case .heading: "textformat.size"
    case .bold: "bold"
    case .emphasis: "italic"
    case .list: "list.bullet"
    case .checklist: "checklist"
    case .link: "link"
    case .quote: "text.quote"
    case .code: "chevron.left.forwardslash.chevron.right"
    }
  }
  var title: String {
    switch self {
    case .heading: String(localized: "Heading")
    case .bold: String(localized: "Bold")
    case .emphasis: String(localized: "Italic")
    case .list: String(localized: "Bullet list")
    case .checklist: String(localized: "Checklist")
    case .link: String(localized: "Link")
    case .quote: String(localized: "Quote")
    case .code: String(localized: "Code")
    }
  }
  func apply(to selection: String) -> String {
    switch self {
    case .heading: "## " + selection
    case .bold: "**" + selection + "**"
    case .emphasis: "_" + selection + "_"
    case .list: selection.components(separatedBy: "\n").map { "- " + $0 }.joined(separator: "\n")
    case .checklist:
      selection.components(separatedBy: "\n").map { "- [ ] " + $0 }.joined(separator: "\n")
    case .link: "[" + selection + "](https://)"
    case .quote: selection.components(separatedBy: "\n").map { "> " + $0 }.joined(separator: "\n")
    case .code: "```\n" + selection + "\n```"
    }
  }
}
