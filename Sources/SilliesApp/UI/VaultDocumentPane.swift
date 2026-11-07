import Foundation
import SilliesCore

/// The visible document surface is independent of the last loaded text section.
enum VaultDocumentPane: Hashable {
  case screenshot
  case text(VaultDocumentSection)
  case files

  init(section: VaultDocumentSection) {
    self = section == .files ? .files : .text(section)
  }

  var title: String {
    switch self {
    case .screenshot: String(localized: "Screenshot")
    case .text(let section): section.title
    case .files: String(localized: "Files")
    }
  }
}
