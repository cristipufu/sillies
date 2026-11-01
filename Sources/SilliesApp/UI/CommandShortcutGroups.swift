import Foundation
import SilliesCore

enum CommandShortcutGroup: String, CaseIterable, Identifiable {
  case dictation, skills, selection, library
  var id: Self { self }
  var title: String {
    switch self {
    case .dictation: String(localized: "Dictate into another app")
    case .skills: String(localized: "Start a mascot skill")
    case .selection: String(localized: "Edit selected text")
    case .library: String(localized: "Vault & companions")
    }
  }
  var explanation: String {
    switch self {
    case .dictation:
      String(
        localized:
          "Focus a text field first. An available mascot listens; finishing inserts your words there. Audio isn’t saved."
      )
    case .skills:
      String(
        localized:
          "An available mascot starts the same skill you use from its menu or wheel. Window skills use the foreground app."
      )
    case .selection:
      String(
        localized: "Select text in another app first. A companion edits that selection on this Mac."
      )
    case .library:
      String(
        localized: "Open saved material or manage the crew. These actions don’t start recording.")
    }
  }
  var commands: [AppCommand] {
    switch self {
    case .dictation: [.holdDictation, .toggleDictation, .cancelDictation]
    case .skills: [.record, .listen, .participate, .snap, .explain, .chat]
    case .selection: [.shortenSelection, .fixSelectionGrammar, .translateSelection]
    case .library: [.saveClipboard, .searchStash, .openVault, .dictationHistory, .togglePause]
    }
  }
}

extension AppCommand {
  var shortcutExplanation: String {
    switch self {
    case .holdDictation: String(localized: "Hold to speak. Release to finish and insert.")
    case .toggleDictation:
      String(localized: "Press to start. Once listening, press again to finish and insert.")
    case .cancelDictation:
      String(localized: "Stop dictation or selection editing without inserting.")
    case .record: String(localized: "Save microphone audio, a transcript, and notes in the Vault.")
    case .chat:
      String(localized: "Open a conversation with a companion. Type or use the microphone.")
    case .listen:
      String(localized: "Transcribe a meeting from the foreground app and your microphone.")
    case .participate:
      String(localized: "Listen to the meeting and offer suggestions through your mascot.")
    case .snap: String(localized: "Save an image of the foreground window.")
    case .explain: String(localized: "Read and explain the foreground window.")
    case .shortenSelection: String(localized: "Replace the selection with a shorter version.")
    case .fixSelectionGrammar: String(localized: "Correct grammar while keeping your meaning.")
    case .translateSelection:
      String(localized: "Use the translation language selected in Writing settings.")
    case .saveClipboard: String(localized: "Save the current clipboard to Pocket Stash.")
    case .searchStash:
      String(localized: "Choose saved text to paste into the app you started from.")
    case .openVault: String(localized: "Browse captures, recordings, transcripts, and stashes.")
    case .dictationHistory:
      String(localized: "Copy or delete the last 20 dictations and selection edits.")
    case .togglePause: String(localized: "Pause or resume mascot activity.")
    }
  }
}
