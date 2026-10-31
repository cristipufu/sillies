import SilliesCore

enum CommandShortcutGroup: String, CaseIterable, Identifiable {
  case dictation, skills, selection, library
  var id: Self { self }
  var title: String {
    switch self {
    case .dictation: "Dictate into another app"
    case .skills: "Start a mascot skill"
    case .selection: "Edit selected text"
    case .library: "Vault & companions"
    }
  }
  var explanation: String {
    switch self {
    case .dictation:
      "Focus a text field first. An available mascot listens; finishing inserts your words there. Audio isn’t saved."
    case .skills:
      "An available mascot starts the same skill you use from its menu or wheel. Window skills use the foreground app."
    case .selection:
      "Select text in another app first. A companion edits that selection on this Mac."
    case .library:
      "Open saved material or manage the crew. These actions don’t start recording."
    }
  }
  var commands: [AppCommand] {
    switch self {
    case .dictation: [.holdDictation, .toggleDictation, .cancelDictation]
    case .skills: [.record, .listen, .participate, .snap, .explain]
    case .selection: [.shortenSelection, .fixSelectionGrammar, .translateSelection]
    case .library: [.saveClipboard, .searchStash, .openVault, .dictationHistory, .togglePause]
    }
  }
}

extension AppCommand {
  var shortcutExplanation: String {
    switch self {
    case .holdDictation: "Hold to speak. Release to finish and insert."
    case .toggleDictation: "Press to start. Once listening, press again to finish and insert."
    case .cancelDictation: "Stop dictation or selection editing without inserting."
    case .record: "Save microphone audio, a transcript, and notes in the Vault."
    case .listen: "Transcribe a meeting from the foreground app and your microphone."
    case .participate: "Listen to the meeting and offer suggestions through your mascot."
    case .snap: "Save an image of the foreground window."
    case .explain: "Read and explain the foreground window."
    case .shortenSelection: "Replace the selection with a shorter version."
    case .fixSelectionGrammar: "Correct grammar while keeping your meaning."
    case .translateSelection: "Use the translation language selected in Writing settings."
    case .saveClipboard: "Save the current clipboard to Pocket Stash."
    case .searchStash: "Choose saved text to paste into the app you started from."
    case .openVault: "Browse captures, recordings, transcripts, and stashes."
    case .dictationHistory: "Copy or delete the last 20 dictations and selection edits."
    case .togglePause: "Pause or resume mascot activity."
    }
  }
}
