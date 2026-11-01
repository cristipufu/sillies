import Foundation

/// Stable command identities shared by keyboard, menus, and companion gestures.
public enum AppCommand: String, CaseIterable, Codable, Sendable, Identifiable {
  case listen, participate, snap, explain, record, chat, saveClipboard, openVault, togglePause
  case holdDictation, toggleDictation, cancelDictation, dictationHistory
  case searchStash
  case shortenSelection, fixSelectionGrammar, translateSelection

  public var id: String { rawValue }
  public var startsWriting: Bool {
    switch self {
    case .holdDictation, .toggleDictation, .shortenSelection, .fixSelectionGrammar,
      .translateSelection:
      true
    default: false
    }
  }
  public var skill: CompanionSkillKind? {
    switch self {
    case .listen: .listen
    case .participate: .participate
    case .snap: .snap
    case .explain: .explain
    case .record: .record
    case .chat: .chat
    default: nil
    }
  }
  public var title: String {
    if let skill { return skill.title }
    return switch self {
    case .saveClipboard: String(localized: "Save Clipboard")
    case .openVault: String(localized: "Open Vault")
    case .togglePause: String(localized: "Pause / resume companions")
    case .holdDictation: String(localized: "Hold to dictate")
    case .toggleDictation: String(localized: "Start / finish dictation")
    case .cancelDictation: String(localized: "Cancel dictation")
    case .dictationHistory: String(localized: "Recent writing")
    case .searchStash: String(localized: "Search and paste Pocket Stash")
    case .shortenSelection: String(localized: "Shorten selected text")
    case .fixSelectionGrammar: String(localized: "Fix selected text’s grammar")
    case .translateSelection: String(localized: "Translate selected text")
    default: rawValue
    }
  }
}
