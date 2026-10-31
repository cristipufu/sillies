import Foundation

/// Stable command identities shared by keyboard, menus, and companion gestures.
public enum AppCommand: String, CaseIterable, Codable, Sendable, Identifiable {
  case listen, participate, snap, explain, record, saveClipboard, openVault, togglePause
  case holdDictation, toggleDictation, cancelDictation, dictationHistory
  case searchStash
  case shortenSelection, fixSelectionGrammar, translateSelection

  public var id: String { rawValue }
  public var skill: CompanionSkillKind? {
    switch self {
    case .listen: .listen
    case .participate: .participate
    case .snap: .snap
    case .explain: .explain
    case .record: .record
    default: nil
    }
  }
  public var title: String {
    if let skill { return skill.title }
    return switch self {
    case .saveClipboard: "Save Clipboard"
    case .openVault: "Open Vault"
    case .togglePause: "Pause / resume companions"
    case .holdDictation: "Hold to dictate"
    case .toggleDictation: "Start / finish dictation"
    case .cancelDictation: "Cancel dictation"
    case .dictationHistory: "Dictation recovery history"
    case .searchStash: "Search and paste Pocket Stash"
    case .shortenSelection: "Shorten selected text"
    case .fixSelectionGrammar: "Fix selected text’s grammar"
    case .translateSelection: "Translate selected text"
    default: rawValue
    }
  }
}
