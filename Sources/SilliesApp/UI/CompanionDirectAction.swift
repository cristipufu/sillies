import AppKit

/// Display metadata and commands for actions that belong to a companion, not a window.
enum CompanionDirectAction: CaseIterable, Identifiable {
  case chat, talk, record, stash
  var id: Self { self }
  var title: String {
    switch self {
    case .chat: String(localized: "Chat")
    case .talk: String(localized: "Talk")
    case .record: String(localized: "Record")
    case .stash: String(localized: "Pocket Stash")
    }
  }
  var symbol: String {
    switch self {
    case .chat: "bubble.left.and.bubble.right.fill"
    case .talk: "waveform"
    case .record: "mic.fill"
    case .stash: "tray"
    }
  }
  var command: CompanionMenuAction {
    switch self {
    case .chat: .skill(.chat)
    case .talk: .talk
    case .record: .skill(.record)
    case .stash: .openStash
    }
  }
  @MainActor var titleWidth: CGFloat {
    let font = NSFont.systemFont(ofSize: 10.5, weight: .bold)
    let rounded =
      font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 10.5) }
      ?? font
    return ceil((title as NSString).size(withAttributes: [.font: rounded]).width) + 16
  }
}
